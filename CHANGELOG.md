# Changelog

All notable user-facing changes to PeTTa are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The history before
1.0.5 remains available through the repository tags and release notes.

## [Unreleased]

### Added

- The engine boots through SWI's Quick Load Format: every engine and lib
  Prolog source compiles to a `.qlf` beside itself on the first boot and
  loads from it afterwards, taking a warm CLI boot from 0.19s to 0.07s
  on the reference box (the study behind it measured 2.37x in
  instructions with byte-identical output). Freshness is transitive:
  `engine/qlf_boot.pl` purges the whole `.qlf` set when any engine or
  lib source is newer or when the set was written by a different SWI
  version, because SWI's own check covers only a `.qlf`'s immediate
  source and the engine's unit files are consulted by umbrellas. A
  read-only tree skips generation and loads source unchanged. The
  `.qlf` files and version stamp are per-install build artifacts,
  never shipped.
- Add package-level `superpose`, ambient `match`, pre-add verdict builders,
  live container `view`, and the `spawn`, `race`, `every`, `channel`, and
  `par_map` coordination family.
- Add atom-valued named spaces, including ground parametric expression names
  that round-trip through MeTTa source.
- Add plain annotated-class definitions with constructor terms, field
  accessors, construction-time defaults, `__match_args__`, and `__replace__`.
- Add `Space.pre_add` compiled judges with accept, transform, refuse, and
  drop verdicts.
- Add the lazy default-engine module tier for `define`, `cache`, `stats`,
  `limits`, `strict`, and `trace`, including scoped stack-byte limits
  through `petta_py_limited/6`.
- Add Python match-statement lowering to ordered MeTTa case towers and
  `functools.reduce` lowering for named and lambda reducers.
- Add structured documentation emission for descriptions, parameters,
  returns, types, kinds, examples, record fields, and offline
  generated-function help.
- Python-defined equality and truthiness now execute in the Prolog engine for
  native wire values (variables, booleans, numbers, strings, symbols, and
  expressions recursively), with the exact Python semantics: `1 == 1.0`,
  `True == 1`, `-0.0 == 0.0`, and `NaN != NaN`. Opaque grounded objects keep
  the Python dispatch so `__eq__` and `__bool__` stay authoritative. A
  compiled body written with Python operators now lands within 1.06x of the
  same body written with MeTTa's named `==`, from 1.71x before.
- `(with-pragma! ((stack-limit N)) Expr)` scopes SWI's combined stack byte
  ceiling for the expression and restores the previous value on every exit,
  distinct from the reduction-fuel `max-stack-depth` pragma. The host seam
  `petta_py_limited/6` threads the same bound with a negative-value no-bound
  sentinel; `petta_py_limited/5` is unchanged.
- `petta_py_function_generation/1` exposes the process-global `fun/1`
  catalogue generation for cheap host cache invalidation. It reads SWI's own
  `last_modified_generation`, so definitions bump it, evaluation and data
  writes do not, and translator-rule changes are neutral because they do not
  affect `petta_py_builtins/1`.
- `@petta.rules` turns a generator whose parameters are rule-local variables
  into a list of ordinary equation atoms, and `equation(lhs).to(rhs)` keeps the
  two halves on one static Python type. Add the result with `m.add(*laws)`;
  `S["="](lhs, rhs)` remains the explicit longhand.
- `Space.doc(subject)` and module-level `metta.doc(subject)` answer the
  engine's structured `(@doc-formal ...)` atom for one subject, the receiver
  spelling of `get-doc` beside `Space.type`; a subject with no documentation
  raises. The async handle mirrors it. The door embeds the handle's own atom
  rather than the `&self` symbol, so it reads the right space from any
  handle.
- Pure-Python twins now cover 204 of the 223 example programs and 1,367 of
  1,380 runnable forms in those files. The coverage check also records every
  remaining example or form as structured residue against the Phase 14
  authoring feature that Python still lacks.
- Pure recursive source functions are memoized automatically when one rule
  body calls their strongly connected component at least twice. Single-call
  recursion stays uncached, and the shared effect analysis refuses automatic
  caching for state, space, or other impure work. `(cache f force)` and
  `(cache f refuse)` catalog declarations override the profitability choice,
  `explain` reports the decision, and automatic entries preserve duplicate
  answer bags through `lib_memo`. An explicit `lib_tabling` answer trie takes
  precedence until it is removed, so set and bag caches never stack.
- Which reaction fires first is a declared policy. `(agenda <ctx> <policy>)`,
  or `m.declare_agenda(name, policy)`, picks between `declaration` (the
  order they were declared, the stated default and what the engine used to
  produce by accident), `recency` (most recently declared first),
  `specificity` (most tests in the pattern first), `priority` (each
  reaction's own declared number, highest first, written as the optional
  fifth argument of `(on ...)` or `declare_reaction(..., priority=)`), and
  `user`, which names a MeTTa function that scores a reaction. Every policy
  breaks ties on declaration order, and a reaction with no declared priority
  reads as 0, so nothing written before this changes meaning.
- `lib_thread` gains Linda's two blocking binds over a space.
  `(take-atom &space (job $n))` waits until a matching atom is there, then
  removes exactly one and answers it; `(peek-atom &space (job $n))` waits and
  leaves it, which is what `await-atom` already did and now names. Both take
  an optional deadline in seconds. Under contention two takers never claim
  the same atom, so a worker pool is a take in a loop rather than
  `lib_thread` internals. The non-blocking pair needs nothing new: `match` is
  Linda's `rdp` and `remove-atom` its `inp`. A context that declares no event
  delivery is refused rather than parked on a channel that will never report.
- The engine's change events are a first-class public object. `m.events()`
  answers the stream of `(action, space, atom)`, and `EventStream.fold(step,
  space=, pattern=, on=, state=)` is the one way to consume it: a step
  `(state, event) -> state` run inside the write that caused the event, with
  `take()`, `wait(timeout)` and `cancel()` on the handle it returns. The
  three shipped models are now that fold with three different steps, so a
  consumer you write and one this library ships are the same kind of thing:
  `subscribe` delivers, `bridge` writes, and a declared `(on ...)` reaction
  evaluates. `EventStream.publish` announces a change this process did not
  write, which is how a provider with a channel of its own delivers.

- The stdlib phrasebook: every operation MeTTa's standard library declares,
  and what you write in Python instead, at
  `website/reference/stdlib-phrasebook.md`. 136 of 179 surface operations
  have a Python spelling; 115 of them dissolve into Python's own syntax,
  protocols and standard library with no `petta` name at all, 16 wear one and
  5 stay instruction-tier. The page is generated from rows that EXECUTE:
  the lane runs both sides of each row and compares three columns, the MeTTa
  form on LeaTTa as the oracle, the same form on this engine, and the Python
  spelling here, so a spelling that stops answering what it claims is a
  failure rather than stale prose. Over the 121 rows that run both sides the
  MeTTa forms cost 150,082 engine inferences and the Python spellings 6,676,
  and 90 of the 121 cost the engine nothing at all.

- The thirteen ruled doors land: `solve(pattern, subject)` answers
  caller-named binding rows; `typed()` and `arrow()` route Python
  annotations through the type table; `if_`, `not_`, `and_`, `or_`, and
  `in_` build keyword terms; `watch(pattern)` yields change events until
  closed; `@space.define` accepts classes and `space.type(atom)` is the
  get-type accessor, retiring the separate record decorator; `State[T]`
  wraps the state triple as one typed handle; `operator` and fourteen
  `math` callables encode as mentions by identity with compiled-call
  adapters for Python-only argument order; atom `<` uses the engine's
  elementwise order; solve rows hash, so `set(rows)` collapses
  duplicates; `Rules.lower(strategy, requires=)` stores, declares, and
  registers a lowering in one call; `transaction(callable)` keeps
  Python's exception law while `transaction(term)` keeps the engine's
  answers law; and an unmatched defined call stays visible under the
  configured no-match policy.

- Compiled bodies carry MeTTa mentions directly: `S.name` and `V.name`
  lower into atoms by lexical identity with the total
  underscore-to-hyphen map (brackets stay exact), a body-minted `V.hole`
  is a hole for a backwards call to fill, and `petta.fn` is an inert
  package-root namespace generated from the engine catalog with a
  209-attribute lint-clean stub, so a hyphenated or banged callee is an
  ordinary Python attribute. Shadowed builders and host attributes
  refuse at compile time, and one resolver rule (exact, then mapped,
  then the only remaining bang form) governs calls, purity derivation,
  loop sources, and `yield from`.
- A `Space` is a grounded atom, so a space handle crosses term positions
  as an operand: `import!`, `metta`, `add-atom` inside built expressions,
  spawned writes, computed targets, and `context-space` all carry the
  handle itself rather than a rebuilt name. The wire vocabulary gains an
  injective portable `p` tag for space references that round-trips
  through JSON, Janus, the writer, both snapshot formats, and digest.
  The handle also gains `peek(pattern, deadline=)` and `take(pattern,
  deadline=)`, the engine's blocking Linda verbs, with async mirrors
  that wait on the engine worker rather than the event loop.
- Calling a function handle answers an `Answers` view: lazy, cached, and
  replayable, so ordinary iteration is the streaming door, `answers.one()`
  requires exactly one answer, `answers.first(default=...)` requires an
  explicit absence default, and `bool(answers)` pulls at most one. Scalar
  doors decode grounded values and raise error answers; iteration keeps
  `(Error ...)` and `Undefined` as data. `space.fn` is a bound fail-fast
  namespace: attributes transliterate underscores to hyphens, brackets
  preserve exact punctuation, and unknown names raise at access.
- A generator definition whose body is a flat sequence of independent
  `yield` statements stores one equation per yield, and a same-head
  redefinition replaces the whole unit transactionally. Conditional and
  loop-contained yields still compile to one `superpose` equation. Bare
  `@rules` answers an immutable bundle that `space += bundle` lands;
  `@space.rules` collects and lands in one ceremony.
- The walrus is the compiled let expression: `(y := f(x)) + y` in a
  return, a binding's right side, a bare expression, an if test, a for
  iterable or a match subject hoists as a `let*` chain around the
  statement's continuation, PEP 572's enclosing-scope binding read as
  MeTTa's own sequencing. Nesting binds inner-first and siblings bind left
  to right. A while-test walrus (which would rebind per iteration) and a
  walrus inside a nested scope refuse naming the rewrite.
- Sequence variables. A pattern child may now be a gap standing for a RUN of
  children: `...` is anonymous and every occurrence of it is its own variable,
  `(:seg $x)` is named and answers the run it took. `(match &s (A ... D) $t)`
  reads every arity the gap spans, `(let ($pre ... SEP ... $post) $row ...)`
  enumerates the splits, and a `case` arm destructures with one. In Python,
  `...` is the same glyph, `seg(V.rest)` builds the named form, and
  `case (S.Order, id, *rest):` lowers a star pattern to a segment variable.
  A segment binding answers as the Expression its children make.

  The fence is the law's own theorem rather than caution: general sequence
  unification is infinitary (Kutsia, Journal of Symbolic Computation 42(3),
  2007, Theorem 62), so an ask outside the three fragments proved finite there
  refuses and names the rule. The three are a gap-free side, every gap linear
  and a direct child of the root (Section 6.2), and every gap the last child of
  its own expression (Section 6.3). One name may not be both a gap and an
  ordinary variable.

  A pattern with no gap pays nothing: the question is answered by the walk that
  already lifts a pattern's modifiers, and the two matching doors dispatch a gap
  pattern by a wrapper an ordinary pattern never carries. Every benchmark pin is
  unchanged.
- `atom-subst`, the reference's own one-variable substitution:
  `(atom-subst <value> <variable> <template>)` with all three operands as
  written and the result as produced.
- Add sequence variables in equation heads: `(:seg $x)` matches one-sidedly
  per the reference's own rule, a written `(:seg $x)` on the right-hand side
  splices its bound run, a top-level segment spans call arities, splits
  enumerate shortest-first, and a name may occur in both segment and
  ordinary roles with the ordinary occurrence projecting the run's
  expression.
- Add `metta-thread`, the reference's typed full-evaluation instruction:
  mask-directed argument evaluation, one minimal step per iteration, inert
  collapse-bind carriers, and result finality deciding the loop exit.
- Add the reference's `interpret` entry, `noreduce-eq`, and `(%Rest% T)`
  variadic parameter types, with the arrow constructor itself declared
  `(: -> (-> (%Rest% Type) Type))`.
- Add the C reader: `engine/reader.c` parses shipped-mode sources in place
  of the Prolog grammar whenever `engine/reader.so` is built beside it (a
  100,000-atom parse drops from 26.5 million inferences and 795 ms to 7
  inferences and 71 ms), with the Prolog grammar remaining the
  specification, the custom-token path, and the fallback;
  `tests/prolog/reader_c.plt` holds the two byte-equal over the shipped
  corpus, an adversarial battery, and 250,000 generated number spellings.

- Add the store wave: a source's equations are registered when they arrive
  and translated when something first reaches them, with the reachable set
  falling out of the translator's own recursion (s(CASP)'s query-slice
  shape). A deferred function is one marker row per (arity, owning load);
  its equations stay in the space, which already indexes them, and SWI's
  own undefined-predicate retry hook is the safety net under every door the
  engine does not guard itself. Materialisation is interrupt-safe at every
  inference: rows stand until their pair's clauses do, and each equation
  commits clause, fun_meta, provenance and queued types as one transaction,
  so a resource limit landing anywhere leaves the function callable.
  Compiled clauses journal under the source that DEFINED them through an
  ownership pin, so reloading an unrelated file that happened to force a
  function no longer withdraws it. The bulk store door writes a batch of
  data atoms at the mechanical floor (2.25us per atom against 61.39us per
  compiled arrival) with one ordered pass, and the C reader hands back each
  source's function-signature multiset and declaration pairs from the parse
  walk the pre-passes used to repeat. `cons-atom` and `cons` compile inline
  at direct call sites. The two list-constructor inlines, the per-name
  batch collapse, and the duplicate-declaration store probe replace three
  measured quadratic or linear-in-program costs with flat ones.

### Changed

- The four oversized engine sources are reorganized into 21 cohesive plain
  source units consulted by their umbrellas (`engine/metta/`,
  `engine/translator/`, `engine/spaces/`, `engine/filereader/`), the largest
  unit 1,452 lines. Consulting rather than hard module boundaries preserves
  predicate ownership, clause order, and meta-call context, so the split is
  behavior-preserving: all 223 example outputs are byte-identical, the host
  scoreboard is unchanged, and every inference growth slope matches exactly.
- Rename the Python distribution to `pymetta` and its import module to
  `metta`: install with `pip install pymetta` and use `import metta`.
  Neither `petta` nor `pymetta` remains an importable module.
- Rename `Space.query` and `AsyncMeTTa.query` to `match`, and expose
  default-space matching as `metta.match`. No `query` compatibility alias
  remains.
- Remove the legacy `python.petta` wrapper and the root `PeTTa` and `HERE`
  exports. Use `MeTTa`, a `Space` receiver, or bare `metta.match()`.
- Map Python operator words consistently across `S`, static `fn`, and bound
  `space.fn` while keeping bracket names exact and refusing composite-only
  `neg` and `floordiv` words.
- Make space subscripts treat a head-shaped tuple as one pattern, complete
  expression arguments as a join, bulk `+=` as a stream of atoms, and
  pattern deletion as an all-match operation that raises `KeyError` when
  empty.
- Make the query door return lazy `Answers` with bounded cardinality reads,
  engine-side length, same-kind slicing, and the shared projection protocol;
  retain `Rows` as the explicit eager face.
- Make `Expression` collect iterables, preserve its type under slicing, and
  snapshot a space in assembly order.
- Make unary plus preserve atom identity, map implicit operation names
  through the define naming ladder, and align Python atom ordering with
  engine `msort`.
- Keep empty evaluation distinct from unreduced terms and make strict
  evaluation reject only non-reduction.
- Make space length depend on a provider's declared `Sized` support, keep
  handle truth independent of emptiness, and document native iteration as a
  snapshot.
- Move builtins-cache invalidation from every evaluation to generation
  comparison on function-namespace cache reads using
  `petta_py_function_generation/1`. Removing the per-evaluation catalogue
  sniff puts `py-method-call` at 1,503,497,066 instructions, below its
  1,508,773,364 acceptance ceiling.
- Translating a nested expression costs work linear in its depth rather than
  quadratic. A data head is translated by the recursive call that produces it,
  and the compiler then walked that result again looking for function calls
  already translated, which costs the head's whole size at every level. A form
  nested 400 deep cost 322,812 inferences to translate and costs 3,213. Parsing
  the same text was already linear, and every example's output is unchanged.

- Removing an equation no longer costs time that grows with the program.
  Deciding whether a function is still defined anywhere, and whether one module
  owns it, asked for the compiled predicate with its arity left open, which
  walks the module's whole predicate table; the arity registry names the
  candidate instead. Each decision cost 24.9 microseconds in a program of 8,000
  functions and costs 0.59, and removing an equation from one cost 485
  microseconds and costs 384.

- Deciding which memoized functions are recursive costs time linear in their
  number rather than quadratic. A one-member component is recursive exactly when
  it calls itself, and that was asked of the whole arc list once per component,
  so a source of N self-recursive functions, which is what memoization is
  usually asked for, was quadratic to analyse: 3,200 of them cost 156,346
  microseconds and cost 14,783. The arcs the analysis proposes are also matched
  against an indexed node set instead of a list scan, which is what makes a
  file of call sites load in constant time a form.

- Loading a program costs time linear in its size rather than quadratic. Each
  dependency-graph edge is now keyed by a hash of its endpoints, where before
  the edge relation could only be indexed by its node kind: four kinds over
  32,000 edges gave the whole relation an eight-bucket index, so every
  duplicate-edge check during compilation scanned a quarter of the graph.
  Loading 8,000 function definitions cost 3.25 seconds and costs 0.73, and the
  same 500-form batch loaded into a 16,000-form program cost 666 microseconds a
  form and costs 101. Small programs are unchanged.

- Compiling a call site costs nothing that grows with the callee's equation
  count. The specializer read every equation of the callee at every call site to
  decide whether a specialization was worth planning, which was linear in the
  equation count: against a 2,048-equation function one call site cost 64,191
  inferences and costs 682. A call whose arguments are all atomic and none of
  them a function cannot specialize whatever the equations look like, and that
  is now settled from the arguments first. The same specializations are created.

- A conjunctive `match` costs work linear in its conjunct count rather than
  quadratic. Whether every conjunct was relational is a precondition of the
  whole conjunction and it was re-decided at every step, walking the remaining
  conjuncts once per conjunct. A 64-conjunct path query cost 3,416 inferences
  an answer and costs 814; a two-conjunct one is unchanged.

- Reading an expression's shape no longer walks it. A MeTTa expression is a
  proper list, and the engine asked `is_list/1` to confirm that, which traverses
  the whole list to answer what the first cell already says. `(index-atom $l 0)`
  over 25,600 elements cost 34.2 microseconds and costs 0.29, `get-metatype`
  33.4 and 0.33, and `is-expr` 31.5 and 0.12; none of the three moves with the
  list's length any more, so indexing a list inside a loop over it is linear
  rather than quadratic.

- `cons-atom` and `cons` refuse a tail that is not an expression, as the
  specification's own `cons-atom` does. `!(cons-atom a 1)` used to build a term
  the engine could not then print, failing with "cannot write 1 as MeTTa text
  because its printed form would read back as a different value"; it now answers
  `(Error (cons-atom a 1) (BadArgType 2 Expression Number))`. A tail whose type
  is undecided, an undeclared symbol, is still left unreduced, and an unbound
  tail still builds, so `(cons $x $xs)` remains a pattern and the third argument
  still decomposes a list.

- Matching a list against `()` no longer walks the list. `(unify $l () ...)` is
  the other way a MeTTa program tests for the end of a list, and the custom
  matcher classified both operands with `is_list/1`, so every step of a walk
  traversed the whole remaining list. A cons cell and `()` can never match, and
  that is now decided from the first cell. A recursive generator that ends its
  list this way cost 7,550 microseconds over 3,200 elements and costs 1,112, and
  one probe of a 6,400-element list against `()` cost 9.16 microseconds and
  costs 0.32. Answers are unchanged.

- Walking a list to its end is now linear in the list's length rather than
  quadratic. `(== $l ())` is how a MeTTa program tests for the end of a list,
  and deciding whether the two operands were comparable asked `is_list/1` of
  the whole remaining list at every step. One proper list is all that decision
  needs and `()` is one, so an operand that is `()` now settles it without
  walking the other. Traversing 12,800 elements cost 137,949 microseconds and
  costs 26,883, and one comparison against a 6,400-element list cost 8.88
  microseconds and costs 0.53. Answers are unchanged.

- A recursive function that produces several answers now enumerates them in
  time linear in the answer count rather than quadratic. Such a function
  produces its i-th answer at recursion depth i, and the translator left a
  runtime `Out = V` trailing the recursive call, which put that call out of
  tail position. Enumerating K answers cost 903 microseconds at K=400, 12,227
  at 1,600 and 192,516 at 6,400; it costs 111, 404 and 1,906. The same
  generator written directly in Prolog was linear at every size, so the
  quadratic was the engine's own.

- Automatic memoization no longer reads the whole program to decide what to
  cache. Reconciling a source whose call graph changed enumerated every
  equation in the module to find the ones carrying a `(cache f force)` or
  `(cache f refuse)` declaration, and looking one function's equations up
  walked every equation in the engine because the store is keyed on the whole
  source term. Compiling a two-form source containing one call into a space
  already holding 3,200 equations cost 37,831 inferences and costs 2,615, the
  same reading as at 200 equations; 20,000 lookups of one function's equations
  against a module of 3,200 cost 2.52 seconds of CPU and cost 0.012.

- Loading a source that defines a function AFTER the definitions calling it
  is now linear in the number of those call sites rather than quadratic.
  Repairing one caller walked every stored equation in the system to find the
  ones it had to rebuild, so a file with N such callers walked N times over N
  equations. The three places that did so ask through the clause index
  instead. A file of N definitions calling a callee defined last cost 324,456
  inferences at N=100 and rose 3.04x per doubling to 29,981,872 at N=3,200; it
  now costs 304,576 and rises exactly 2.00x per doubling to 9,505,560. The
  same file with the callee written FIRST is unchanged to the inference at
  every size.

- The canonical atoms `TRUE`, `FALSE`, `UNIT`, and `HERE` are public
  values at the package root, so a program names them instead of
  reconstructing their spelling. The twin corpus grew to 218 files, its
  budget lane records asymmetric measured envelopes scoped to their
  measurement protocol instead of a symmetric spread guess, and 159
  structured-residue entries retired against features that now exist.

- The Python surface narrows to a lazy core. `MeTTa` is the runtime
  context, 20 public attributes down from 90; its default space is
  `MeTTa().self` and storage and query verbs live on the `Space` handle.
  `dir(petta)` answers 61 names down from 152, a fresh `import petta`
  loads 9 modules down from 58 and takes 12ms down from 40, and every
  specialist surface (`algebra`, `arrays`, `events`, `wire`, `tables`,
  `paths`, `derivation`, `foreign`, `casting`, and the rest) loads on
  first access under PEP 562. Public atom types use complete Python
  class names: `Symbol`, `Variable`, `Expression`, `Grounded`. Deleted
  without aliases, each with its one door: `new_space`/`fresh_space`
  (`petta.space()`), `count` (`len(space)`), `space_name` (`.name`),
  `register_op` (`op`), `run(using=)` (`with m.bind(...)`), `one`,
  `first` and `stream` (the answer API), `save(space, path)`
  (`space.save(path)`), `val`/root `encode` (`ground` and
  `petta.wire`), `petta.das` and `petta.persistent`
  (`petta.space(backing=...)` and `petta.space(journal=...)`),
  `backend_info` (`petta.engine().info()`), and the root re-exports of
  errors, protocols, events, and proof detail, which live on their
  satellites. Upstream's `python.petta` wrapper is unaffected.

- The supported Python floor is 3.12, raised from 3.11. Every generic
  declaration in `petta` now uses the type-parameter syntax the class shape
  itself carries (`class Defined[**P, R]`, `def build[BuildT](...)`) instead
  of module-level `TypeVar` and `ParamSpec` assignments, and `pip` refuses
  3.11 rather than installing a package whose source it cannot parse.

- Every Python twin is written in the library's own notation rather than in
  s-expressions with Python punctuation. A plain tuple is an expression,
  `S.name` replaces `S["name"]` wherever the name is a Python identifier,
  `equation(head).to(body)` replaces `S["="](head, body)`, an operator replaces
  the naming door wherever an operand is an atom, and a definition whose whole
  body has a compiled spelling is an ordinary `@m.define` function or a
  `@rules` generator. A twin that deliberately sits below the highest rung says
  so where a reader meets it: `# rung: <reason>` on the line that drops, or
  `RUNG = "<reason>"` for a whole file, both read by the coverage check, and
  the reason names the spelling the surface is missing. Answers,
  alpha-equivalence and the pinned inference budgets are unchanged apart from
  named moves: `control/empty` moved to `@m.define` now that it measures inside
  the parity band, and nine budgets in `reasoning/` and `integration/` moved
  with their attribution.
- The `performance/` twins stay at the container door, and the reason is a
  measurement rather than a preference. Python's `==` inside a compiled body
  lowers to the prelude's `py-eq`, a host crossing, where the term door's
  `.eq` builds MeTTa's own equality; in `superpose_primes` that sits in a
  divisor search's inner loop, and the decorated spelling costs 920,726
  inferences against the term door's 536,577, +71.6%, a regression in the
  benchmark the example exists to run.
- Reading a form that spans lines is now linear in the form's length rather
  than quadratic, in the engine's `(read-form!)` and in the `petta repl` CLI
  alike. Both appended each new line to the whole buffered text and re-scanned
  all of it; the scanner state is now carried from one line to the next. One
  form of 1,600 lines cost 132,673,790,292 instructions and costs 1,497,495,105.
- `petta repl` no longer hangs on two inputs the engine considers finished: a
  backslash escaping a line break inside a string, which its check read as an
  unterminated string, and an over-closed buffer holding an unterminated string,
  where the stray bracket now ends the form so it errors rather than prompting.
- A conjunctive `match` now enumerates the most constrained conjunct first
  rather than following source order, over a native space and over one that
  reads through a parent chain alike. Running the conjunction as a nested loop
  in written order is quadratic where the join's own bound is not: the triangle
  query over a graph with a hub joined to everything in both directions, which
  contains no triangle at all, cost 13,502,606 instructions at 100 edges and
  rose by exactly 4.0x per doubling to 3,620,340,557 at 1,600. Through an
  inherited space it was worse still, 13,818,604,870 at 1,600 edges, because
  every conjunct is matched through the whole read chain. Both are now linear in
  the edge count. Answers and their multiplicity are unchanged; the order in
  which they arrive is not specified and does change.
- Checking an expression against a known tuple type is now linear in the number
  of members rather than exponential. The question was answered by deriving the
  expression's candidate types and comparing each to the one asked about, so the
  cost depended on where that type fell in the enumeration: at thirteen members
  carrying three declared types each, the first candidate cost 312 inferences
  and the last cost 29,496,420. Both are now flat. A member that is itself an
  expression decomposes the same way, where enumerating its types cost
  43,097,295 inferences at eight inner members and now costs 622. Answers are
  unchanged, including for a `:<` edge that widens a whole tuple type.
- Typing an expression with no declared arrow for its head is now linear in the
  number of members rather than exponential. Such an expression is typed
  element-wise, so its type set is the cartesian product of its members' type
  sets, and that product was computed by backtracking: every retry re-derived
  every member to its right. Fifteen members carrying three declared types each
  cost 581,130,797 inferences and now cost 1,722, and seventeen members did not
  finish in 280 seconds. Answers, including their order, are unchanged.
- Calling a `Defined` object now evaluates the call in the space that owns the
  definition and returns its answer list. Use `S[name](...)` to build the call
  as data; calls made while a `@rules` generator is being collected stage as
  terms so rule bodies remain ordinary atoms.
- Subscribability is now a declared capability rather than an inference from
  a provider's write methods. A foreign context says what its change events
  promise, through `m.declare_events(name, delivery, order)`, a Python
  provider's `delivers()`, a Prolog provider's `metta_context_events/3`, or
  an `(events <ctx> <delivery> <order>)` atom in `&petta`; delivery is
  `at-most-once`, `at-least-once` or `per-write-exactly` and order is
  `ordered` or `unordered`. A context that declares nothing is refused a
  subscription, a `bridge` and a `declare_reaction`, naming the missing
  capability, instead of serving a watcher that silently misses writes. A
  native space is unaffected and needs no declaration: every write into it
  already runs the engine's own hooks.
- `lift_pattern_modifiers/3` becomes `lift_pattern_modifiers/4`, answering
  whether the pattern carries a sequence variable from the walk it already
  makes.
- Python's `match` star pattern compiles instead of refusing.
- A `let` whose pattern carries a gap matches that pattern rather than
  evaluating it.
- The option vocabularies render as StrEnum classes instead of tuple
  constants and Literal aliases: `metta.vocabularies` exports one class per
  catalog `(vocabulary ...)` row (`OnError`, `SaveFormat`, `Fidelity`,
  `CacheMode`, ...), each member IS its wire word (`OnError.keep == "keep"`),
  encodes as its symbol, and enumerates with `list(OnError)`. Every
  declaration door's annotation names its vocabulary class
  (`handles(pattern, Fidelity.Exact)`, `save(format=SaveFormat.metta)`,
  `events(order=EventOrder.unordered)`), and bare words remain accepted at
  runtime as the escape hatch, refused loudly outside the vocabulary. A value
  that spells a Python keyword takes a trailing underscore as its member name
  (`RouteKey.global_`); a hyphenated word transliterates
  (`AnswerPolicy.best_first`). The tuple constants and Literal aliases are
  gone, `metta.vocabularies` is a core module now, and the lazy `_policy`
  indirection in `_space` is deleted.
- `Space.image`'s setting words join the catalog: `(vocabulary image-mode
  opaque transparent auto)` with a `(kind image ...)` row, so a junk setting
  refuses at the engine as well as at the Python door, and `ImageMode` is
  generated with the rest.
- The class registry's per-type image declaration renames to
  `(type-image TypeName word)`, dissolving the head it shared with the
  context image policy `(image space type setting)`; its word set is the new
  `registry-image` vocabulary (`expression`, `symbol`, `handle`,
  `operations`), also catalog-validated.
- A parameter declared with a metatype now holds its argument AS WRITTEN at
  every door, which is what `Atom`, `Variable` and `Expression` mean in a
  parameter position. Written builtin calls, the special forms that take a
  list (`map-atom`, `filter-atom`, `foldl-atom`), and the dynamic `eval`,
  `evalc` and `metta` doors all read the same declared mask, and a call whose
  declared result is the metatype `Atom` answers as produced while every other
  declared result re-enters evaluation. `!(car-atom ((+ 1 2) b))` is `3` by
  the arbiter's route rather than by evaluating the operand first, and
  `!(map-atom (cdr-atom (a b)) $y (q $y))` maps over the two parts of the
  unrun call. A caller that wants a call's VALUE in a masked position names it
  first: `(let $xs (collapse ...) (map-atom $xs ...))`.
- Corrected the declarations the engine did not previously honour, so a
  declaration now describes what the operation receives: the SWI-Prolog
  interface predicates and the Python bridge take `%Undefined%` parameters,
  `cons`, `decons`, `first` and `second-from-pair` answer `Atom`, `sort-atom`
  takes `%Undefined%`, `unquote` evaluates its operand, and `map-atom`,
  `filter-atom` and `foldl-atom` carry the arbiter's own pair of arrows.
- `assert` evaluates the form it is given and reports it AS WRITTEN:
  `!(assert (== 1 2))` now names `(== 1 2)` instead of the `False` it reduced
  to.
- `add-reduct` and `add-reducts` reduce a plain atom as well as an equation's
  body, so `(add-reduct &s (total (+ 1 2)))` stores `(total 3)`.
- A late type declaration now rebuilds the declared function's own equations
  as well as its call sites, so `(: f (-> Atom Atom))` arriving after
  `(= (f $x) (g $x))` stops `f` re-entering evaluation.
- A lambda no longer captures a variable its own body binds, so one closure
  applied to many elements no longer lets the first element's binding
  constrain the next.
- Minimal MeTTa's NotReducible protocol is real end to end: `eval` is one
  equality step whose raw three-way result only `chain`, `function`, and
  `metta-thread` observe, every application boundary retains an irreducible
  call as written, a function frame distinguishes a produced marker from an
  irreducible body (`(Error (function <body>) NoReturn)`), and `reduce`,
  `eval`, and `evalc` each retain their own written frame. `repeat`
  terminates and the reference's strategy suite passes whole.
- Bare-symbol arguments follow scalar equality rules to a fixpoint at eager
  positions; a Grounded parameter refuses an evaluated argument of the
  wrong type with `BadArgType`; a declared result decides re-entry and
  never filters the produced value; a declared function called at an arity
  no arrow presents answers `IncorrectNumberOfArguments`; a variable head
  resolves at run time and applies its own mask to still-written arguments;
  `car-atom` and `cdr-atom` of `()` answer the arbiter's exact `Error`
  atoms; `collapse-bind` answers the public `((atom (bindings …)) …)`
  carrier; polymorphic builtin results re-enter evaluation while numeric,
  string, and grounded results stay direct; and `collapse` evaluates an
  operand that arrived through a masked parameter.
- The assert family compares result bags: order is ignored while duplicate
  multiplicity counts, via directed `subtraction-atom` differences under
  the new `noreduce-eq`. `if-error`, `return-on-error`, `match-types`, and
  `is-function` ship the reference's own bodies (`return-on-error` keeps
  one `return` for an enclosing frame at top level), and `unquote`'s
  quote-wrapping catch-all retires.

### Removed

- The namespace call-form aliases: `S("x")`, `V("x")` and `fn("name")` were
  synonyms for attribute access and are gone; `S.x` / `S["exact name"]` and
  `fn.car_atom` / `fn["car-atom"]` are the two doors, one mechanism each.
  The async engine's `fn(name)` method becomes the same namespace property
  as the sync surface: `m.fn.car_atom` transliterates, `m.fn["=="]` is
  exact, resolution stays lazy on the worker.

- Remove all 15 synchronous `declare_*` methods and their async mirrors in
  favor of head-named receiver methods.
- The legacy `python.petta` import path. The alias package that kept
  upstream's `import python.petta` resolving to the canonical modules is
  gone, and `petta` is the only import path. Code spelling the upstream
  checkout layout must import `petta` directly.

- The shipped translator rules' termination is now ESTABLISHED.
  `lib/lib_spaces.metta`'s `succeedsPredicate` writes two variables its head
  does not, and its registration declares, with the reason, that both are
  binders of its own expansion rather than variables taken from the term being
  rewritten. The confluence report prints the exemption beside the termination
  line, a rule that invents a variable and says nothing still reports
  `extra_variables`, and the lane gained a GATE beside its report. The
  obstruction that remains is a different one on a different tier: the
  prelude's three identity rules have their left side inside their right, so
  no path order can orient them, and the compiler terminates on them only
  because `noeval` stops the expansion going round again.
- A translator rule can carry a `(cost N)` and a conjunctive left side.
  The cost prices a form headed by the rule's name and decides which of two
  equivalent forms a bidirectional rule emits, the way an e-graph extractor
  chooses between them. `(left (Pattern ...))` with `(right Expansion)` gives
  a rule several patterns that must all match, the first against the call and
  the rest against the space; they join on the variables they share and
  compile to a `match` chain, so the engine's own conjunctive query does the
  join.
- A translator rule can decline a match it cannot honour, with
  `(refuse Reason)`. The call carries on down the dispatch chain exactly as
  one whose head did not match, so a rule with another equation tries that
  one, and the reason is published into `&petta` as
  `(translator-rule-refusal NAME REASON)` rather than lost. A refusal is a
  rule's own condition written where a reader can see it, so the confluence
  report counts the rules of a set that can refuse and reports such a set
  `NOT DECIDED`, with its critical pairs listed as the proof obligations they
  are.
- A translator rule can declare its direction, and a bidirectional one is a
  single declaration. `!(add-translator-rule! NAME ((direction bidirectional)))`
  derives the inverse equation, adds it to the space and registers the head it
  is rooted at, so the inverse is never written by hand; removing the rule
  removes it again. Which direction fires is decided per call by the form's
  cost, which defaults to its node count, and a rewrite fires only when it
  lowers that cost, so the two directions cannot rewrite each other forever.
  Every precondition of the inversion is checked with the failure named. The
  registry moved to `engine/translator_rules.pl` and holds one row per rule
  instead of a bare name.
- A protected core that a translator rule cannot replace. Registering a rule
  for `eval`, `evalc`, `chain`, `let`, `unify`, `superpose`, `collapse`,
  `call`, `translatePredicate`, `reduce`, `if`, `case`, `catch` or `cut` is
  refused with the name in the message, where before the rule silently went
  ahead of the compiler's own form for the rest of the process. Every other
  head is still yours to take over, and a registration that goes ahead of a
  compiler form or a builtin is recorded and printed by the confluence
  report.
- The compiler now says what it decided about a head pattern position that is
  not plain structure: which argument and subterm, which label, and why. A
  position compiled into a type premise goal and a position whose label already
  has meaning, through equations or through the translator, each get a message
  and a row in the engine's own register. A position whose parameter carries
  the evaluation mask is silent, because there the structural pattern is what
  the caller hands over.
- A translator rule's body is documented as its condition. A clause applies
  when its head matches and its body produces an expansion; a body with no
  answer declines and the next clause is tried; a rule with no applicable
  clause leaves the call to ordinary dispatch. `EXTENDING.md` gains the
  section, `examples/translation/translatorrule_guard.metta` runs it, and the
  confluence report now says that its verdict decides the unconditional system
  it extracts from the rule heads and is a proof obligation about the
  conditional rules that actually run.
- Every file that names the rewriting machinery now states which of narrowing
  and rewriting its own results are about. Confluence and critical pairs are
  rewriting notions; evaluating an equation instantiates the call it was asked
  about, and that is narrowing, which is why `engine/narrowing.pl` reduces the
  one question to the other. A translator rule, by contrast, is applied by
  matching and re-checked after its body runs, so the rewriting results reach
  the rule tier directly. Constructive negation's third sense of the word is
  named too, in `engine/duals.pl`.
- The compiler's hand-threaded state is now pinned by a test. P2.20 measured
  DCG semicontext against the hand-threaded difference lists and closed as
  rejected; `test_no_dcg_semicontext_threads_the_compilers_state` reads
  `engine/translator.pl`'s terms and fails if any translator predicate becomes
  a DCG, while `engine/filereader.pl`'s pushback rule stays allowed and proves
  the detector sees one.
- `+`, `-`, `*` and `/` now solve past their single-unknown mode. Each already
  inverted one unbound slot among integers, so `(= (double $x) (* 2 $x))` read
  backwards and `!(let 10 (double $x) $x)` answered `5`; that fragment is now
  documented in `examples/basics/relational_arithmetic.metta`. Past one
  unknown the engine posts the relation to CLP(FD) and labels what
  propagation leaves, so `!(collapse (let 25 (* $x $x) $x))` answers `(-5 5)`
  and `!(collapse (let 25 (* $x $y) ($x $y)))` answers every divisor pair. A
  domain the constraint leaves unbounded, and every backward query outside the
  integer relations, now refuses with a named reason instead of SWI's bare
  `Arguments are not sufficiently instantiated`.
- SQLite table bridges now honor per-context `image` declarations. The
  shipped example maps a `BLOB` column to a live `Blob` handle under
  `opaque`, lets a lazy path read one byte without projecting the payload,
  and demonstrates the structural crossing selected by `transparent`.
- `petta.spaces.object_view(obj)` now presents live Python fields as
  `(py-field obj name value)` atoms on the ordinary foreign-space seam. The
  view composes with stored spaces for joins, observes later mutations, and
  turns added field atoms into `setattr` writes.
- A one-variable query can now rebuild complete constructor expressions with
  `query(into=Class)`, and the underlying `Rows.build(Class)` door exposes the
  same operation. Multi-column `into=` retains field-name row shaping;
  `cast` remains type admission and returns the admitted atom unchanged.
- Lazy query paths now reach attributes and subscription keys inside opaque
  Python handles after the surrounding stored pattern matches. They read live
  state, join through ordinary query variables, and stop cyclic traversals.
- Atom operators now come from one immutable lowering table. Floor division,
  unary minus, and `abs()` build reducing MeTTa forms; integer shifts name the
  missing engine operation; and `@` explicitly targets library-provided
  `matmul`. Grounded atoms keep the corresponding Python value operations.
- Compiled definitions now expose AST-derived source spans, documentation,
  lexical free variables, and purity. The facts reflect into `&petta`, replace
  with a clause, and leave when its space is cleared.
- Local annotated assignments in `@define` functions now compile to in-place
  MeTTa type claims. The value binds before the premise runs, and annotation
  syntax resolves without arbitrary `eval` or user-defined subscripting.
- `typing.Annotated` metadata now survives as matchable `(Annotated ...)`
  claims while the base type continues to control arrows, conversion, and
  engine-parameter injection.
- All 44 names installed by `petta.arrays` now carry arity-accurate arrow
  declarations, including defaulted and variadic call forms. The new
  `broadcast-shape` CLP(FD) relation checks or infers NumPy broadcasting
  shapes before an array is materialised.
- Python conversion now carries bare and abstract sequence annotations through
  the same container hook as parameterized builtins. Buffer exporters project
  as zero-copy `Buffer` expressions that retain the original object together
  with shape, format, item size, dimensionality, strides, and access metadata.
  Integration entry points may declare `PETTA_REQUIRES`; discovery installs
  them in topological order and refuses duplicate names, missing requirements,
  and dependency cycles by name.
- Declared value algebras name `combine`, `extend`, `zero`, `one`, checked
  laws, an optional finite checking carrier, and context requirements as one
  catalog atom. Ordinary `(fact tag proposition)` and `(rule tag head
  (premises ...))` atoms run through one algebra-agnostic threader. The
  shipped Boolean, bag, set, ranked, probability, provenance, and budget
  algebras are data presets. Nonnegative `(rate n)` tags feed reproducible
  seeded selection without changing unannotated evaluation. A linear algebra
  refuses a derivation that spends the same stored premise occurrence twice.
  Exact complex amplitudes interfere only in contexts declaring the finite,
  contractive, staged fragment; use outside that fence is a named refusal.
  Grounded tensor tags keep their DLPack identity and autograd graph through
  multi-rule derivations for direct consumption by `pettorch.MettaModule`.
  Five pinned Scallop README programs now ship as executable PeTTa witnesses
  with a feature-to-seam table and explicit filed gaps.
- A ground expression can name a native space. For example,
  `!(new-space (cache &kb 100))` creates an isolated storage and execution
  context whose exact identifier is returned by `context-space`; equations
  can destructure it with ordinary `let` patterns to read the family
  parameters. Canonical term encoding gives each instance distinct storage
  and execution modules while ordinary computed space expressions keep
  evaluating as before.
- Restricted spaces use a curated execution base and creation-time
  `file`, `process`, and `network` grants. A denied operation raises a
  structured refusal naming the space, operation, and missing capability;
  raw Prolog calls additionally pass SWI's sandbox classifier. Python exposes
  the same policy through `new_space(restricted=True, grants=(...))`.
- Spaces can inherit from one parent at creation with
  `(new-space &child (inherits &parent))` or
  `runtime.new_space(inherits=parent)`. Atom reads are a child-first multiset
  union and conjunctions join across layers, while adds, removals, clear, and
  `space-atom-count` remain local. The execution module uses the same parent
  chain for equations. Cycles, late declarations, conflicting parents, and
  dropping a parent with a live child are refused before mutation.
- A packaged Ciao-style development grade now applies external `pred`
  assertions to the engine's atom-removal, equation-removal, storage-removal,
  and translation funnels. `assertions@0.0.1`, `rtchecks@0.0.1`, and
  `xlibrary@0.0.2` collect violations as `assrchk/1` data without adding a
  production engine dependency; a clean smoke and a planted bad call gate both
  directions.
- The six function-dispatch decisions are catalog data in `&petta`:
  mismatch, no matching head, evaluation order, result determinism, failed
  clause handling, and exhaustion. Each has a shipped default and accepts a
  `(dispatch-policy <function> <axis> <value>)` override that takes effect on
  already-compiled calls. The conforming no-match default leaves the call
  unreduced.
- `&petta` now publishes `(policy <axis> <knob> <default>)` rows for exactly
  seventeen engine decision axes: dispatch, order, merge, agenda, equality,
  errors, world, algebra, storage, typing, fidelity, source kind, transaction
  mode, atomicity, save format, volatility, and determinism. The new
  `policy-inventory` gate derives that table from the running engine, joins
  every row and the semiring law claims to their implementation seams, and
  rejects unowned closed policy lists. The scanner covers multiline Prolog
  `member/2` and `memberchk/2`, Python `Literal[...]`, and Python list or set
  membership. Exemptions require an adjacent category, reason, and an actual
  local source line or symbol. Save formats, asynchronous declaration types,
  and memo aggregation values consume catalog vocabularies rather than
  duplicate local lists.
- `add-typing-rule!` and `remove-typing-rule!` extend the checker with
  module-scoped rules that answer `accept`, `(refuse <reason>)`, or `defer`.
  The shipped arrow-arity, widening, gradual-compatibility, and metatype rules
  occupy the same registry. A user refusal overrides an overlapping shipped
  acceptance and is retained by name in the resulting `BadArgType`. The
  confluence reporter now has translator and typing family descriptors; it
  reports user/user and user/shipped refusal or defer overlaps as conditional
  proof obligations.
- Derived engine artifacts now share a demand-driven support graph with eager
  dirtiness and stabilization cutoff. Module-qualified forward edges connect
  source functions to specializations, memo generations, translated forms,
  compiled functions, and their callers; changing one support invalidates only
  its reachable dependents, and releasing a pooled space releases its graph
  state. This replaces the specializer, memo, and compile-door dependency walks
  with one cycle-safe mechanism.
- `DontEvalType` is a declarable evaluation mask. Declaring
  `(: Payload DontEvalType)` makes a `Payload` parameter receive its written
  expression before evaluation; the compiler consults the declaration, not a
  type-name convention.
- `(space-atom-count <space>)` answers how many atoms a space holds from
  the store's own per-predicate clause counts: one property read per
  stored arity, none per atom, so a capacity policy over a million-atom
  pool costs what it costs over ten. A never-written space holds nothing;
  an unbound or non-space argument is refused like the sibling builtins;
  a foreign space is refused by name, because its provider owns its atoms
  and the only general count there is an enumeration.
- `(has-declared-type $x $type)` answers whether a `(: $x $type)`
  declaration witnesses the type, about the atom AS ITSELF: the first
  parameter carries the Atom mask, so a policy written in MeTTa can ask
  the admission contract's own question of an unreduced atom.
- `(space-contains <space> <atom>)` answers membership as one indexed
  probe against the store, about the atom AS ITSELF, flat however large
  the space grows: a set-semantics pre-add rule spelled over it costs
  57 inferences per add at 2,000 held atoms and the same at 10,000,
  against 69 for the `collapse`-over-`match` spelling of the same
  question and 27 for a plain add.
- `(space-admission-verdict <pool> <atom>)` is the shipped judge over the
  `(admits <pool> <type>)` and `(capacity <pool> <n>)` contract atoms in
  `&petta`, answering the pre-add hook's own verdict algebra: `(accept)`,
  or `(refuse (does-not-carry <type>))` and
  `(refuse (pool-at-capacity <limit>))` naming the first violated
  contract. `declare_admits` and `declare_capacity` claim a pool's
  pre-add hook with it through a one-line guard equation, and
  `examples/spaces/admission_pools.metta` runs the same judge written in
  MeTTa with a differential asserting the two agree verdict for verdict.

### Fixed

- `space += atom` and `space -= atom` inside a compiled body are the write
  doors: a local bound to `(context-space)` or `(new-space ...)`, or
  aliased from one, compiles its augmented assignment to `add-atom` and
  `remove-atom`, keeping the space name bound while the write executes.
  Before this, `+=` read as arithmetic and stored `(+ $s atom)`, which
  answered `True` and wrote nothing, silently. Any other augmented operator
  on a space refuses naming the two lawful ones; a module-global space
  target refuses naming the compiled write door, and a nested-function
  local keeps Python's own unbound-augmentation refusal.
- `metta.Undefined` in a type position annotates as `%Undefined%`: the
  class represents the metatype, and mapping it by class name built the
  plain symbol `Undefined`, which the engine read as a user type so the
  declaration silently did nothing. `arrow(Atom, Atom, Undefined)` and
  `typed(subject, Undefined)` now spell the same row `typing.Any` always
  spelled.
- The first `m.fn.<name>` access after any definition no longer rebuilds
  the whole builtins catalogue: attribute resolution asks a point
  membership probe, dropping that access from 1,347 engine inferences to
  193 measured, with the list kept for enumeration and a parity test
  holding the two doors to one union.
- A `Defined` function or a bound engine function placed in term position
  now encodes as its own head symbol, the guide's mention rule, so
  `S.memoize(add, 2)` builds `(memoize add 2)` instead of an opaque box the
  engine refuses with a Domain error; `G(fn)` stays the explicit spelling
  for the live object.
- `math.floor`, `math.ceil` and `math.trunc` on an atom build their math
  terms instead of silently coercing through `__float__`, and `round` gains
  its hook (`round(G(5.4))` builds `(round-math 5.4)`); a two-argument
  `round` refuses. The generated unary operator methods also close a
  signature hole where a stray positional argument was absorbed by the
  captured symbol slot and built a wrong term silently.
- A second Python function redefining an installed MeTTa head refuses with
  the collision named and three remedies, where it used to die as a bare
  `IndexError` deep in the twin clause store.
- `m.limits(stack=)` documents that it is SWI's stack ceiling in bytes,
  distinct from the `max-stack-depth` pragma's reduction-step bound.

- `Space.take` and `Space.peek` deadline misses raise `metta.Timeout`,
  the same class every other deadline miss raises, so the guide's
  `except metta.Timeout` clause catches them; it subclasses the builtin
  `TimeoutError`, so existing handlers keep working.
- Stale build directories no longer ride into wheels. A build_lib
  directory that is not a package of the current build is removed before
  building, the package-level half of the clearing the bundled-runtime
  tree already had; after the module rename a stale `build/lib/petta`
  had shipped beside `metta` until the packaged gate's own assertion
  caught the contaminated wheel.
- Data forms loaded from a file now pass through the declared pre-add
  admission hooks, so `declare-pre-add!` accept, transform, drop, and refuse
  verdicts behave identically on the file, host, and running-MeTTa routes.
  The file loader had called the space spine directly, bypassing the hook.
- The published space compliance suite picks the atom its shape-dependent
  checks run against by width rather than by whichever one a provider
  enumerated first. A provider answers its atoms in no particular order, so a
  provider holding both a one-argument and a two-argument atom used to exercise
  the repeated-variable check or skip it depending on order, and adding a single
  never-called predicate to the engine was enough to flip it.
- Dropping or clearing a space that had tabled a function no longer risks
  terminating the process. The clear removed the clauses of predicates that
  were still tabled and only untabled them afterwards, so every removal ran
  against a predicate whose tables and tabling instrumentation were still
  live. The untabling now runs first, before every path that removes a
  clause. Sixty cycles of "table a function in a fresh space, drop it, take
  the recycled name, redefine the same function" ended the process in 3 runs
  of 3 before the change and 0 of 4 after. The defect was old and only
  appeared once enough tabling had accumulated in one process, which is why
  it looked like an occasional flake rather than a fault.
- `@define` now installs an annotation-derived type declaration before its
  equation is compiled. The compiler therefore sees the signature at the door
  where it matters instead of learning it after the clause already exists.
- `yield from f(...)` inside `@define` no longer silently treats an arbitrary
  deterministic result as a nondeterministic answer stream. It delegates only
  to a builtin iterable, the same definition, or a name explicitly marked
  nondeterministic; another known engine call is refused with the two valid
  spellings, `yield f(...)` or binding an iterable before `yield from`.
- A pattern whose head is a variable now answers through every door. The
  match compiler's modifier clauses wrote their `:=` and `:` markers (and
  the Python shim's `path-at`) as literals in their clause heads, and a
  literal unifies with an unbound head instead of rejecting it, so
  `(match &s ($A $B) ...)` bound the program's own `$A` to `:=` and
  answered nothing, a three-element pattern compiled as a type premise,
  and an ordinary three-element query could raise out of the lazy-path
  code. The markers are now read nonvar-then-==, so a variable-headed
  pattern compiles as the ordinary structure it is and MeTTa `match`,
  Python `query` and Prolog `match/4` agree at every arity.
- A grounded atom now equals another grounded atom exactly when the engine
  would unify them, while comparison with a raw Python value keeps the `==`
  operator's numeric tower. One relation served both purposes before, so
  `unify`, membership, `remove` and any dict of atoms disagreed with what a
  space actually stores: the pattern `(0)` claimed to match a stored `(0.0)`
  that the engine keeps distinct, one NaN atom refused to equal another that
  the engine's matcher matches, and a Counter of atoms conflated keys. The
  raw-value comparison keeps IEEE arithmetic, NaN unequal to itself, the
  verdict of the engine's == over crossed values. Found by the space state
  machine's Hypothesis run; the split is the one Java draws between `==` and
  `Double.equals` so hash collections stay coherent.
- `quote` now scopes a pattern exactly as it scopes a body. A quoted head
  pattern is held as written instead of being walked, so `(cons 1 2)` inside
  one stays a two-element expression rather than becoming an improper list and
  `(: $x Number)` stays an annotation rather than becoming a type premise. A
  head written to match what a body writes now matches it.
- A translator rule is applied by matching. Its head shape and its body goals
  can no longer instantiate the call they were asked about, so a rule can no
  longer rewrite the head of the equation that holds the call:
  `(= (uses $z) (rule $z))` keeps `$z` matching anything, and a rule that
  cannot apply falls through to its next clause and then to ordinary dispatch.
- `once` and `take k` over a conjunctive `match` now stop at the bound instead
  of computing every row of the join first. Taking one row of a two-conjunct
  self-join cost 1,328 inferences over ten edges and 6,398 over four hundred;
  it is 1,222 over both now. The bound is pushed only where the whole
  expression is one `match`, so a template that compiles to a call keeps every
  answer, and an unbounded conjunction still finds every row before the first
  one leaves.
- `(take 1 (match $u (f 1) matched))` now answers `match`'s Error atom, which
  the plain `match` always answered. `take` and `top` fused the expression's
  result with its output template while compiling, leaving the answer-shaped
  refusal nothing to unify with, so the query answered nothing at all.
- A table built from a bounded `match` is now invalidated by a write to the
  space it read. The compiled bounded form was a goal the purity walk did not
  recognise, so the read went unreported.
- Modifier-free host queries now choose the empty path before matching, so
  lazy-path support has a fixed preparation cost instead of a cost per answer.
- Generated symbolic atom operators now specialize their lowering table entry
  once at import instead of interpreting that entry for every constructed term.
- Typed local bindings now carry an internal provenance marker, so source-level
  colon pairs remain data patterns even when their third slot looks like a
  concrete type. Existing destructuring programs such as
  `reasoning/nilbc.metta` retain their meaning.
- Prolog extensions may now add `builtin_type_declaration/2` clauses without
  replacing the engine's built-in type table; unloading removes only the
  extension's clauses.

- A required dataclass `InitVar` now refuses during conversion registration
  instead of failing only when its incomplete projection is rebuilt.
  `register_op` refuses unreachable `**kwargs`, and a typed zero-parameter
  operation emits its return arrow instead of remaining undeclared.
- Real-valued `sqrt-math`, `log-math`, and trigonometric operations now
  promote integer operands to Float before evaluation. `pow-math` likewise
  returns Float, accepts an unbounded Float exponent, and refuses an integer
  exponent outside signed i32 with the arbiter's exact Error reason.
- Integer division and remainder by zero now answer the arbiter's contained
  `(Error (<operation> 7 0) DivisionByZero)` atom. Float division by zero
  keeps its IEEE infinity or NaN result, and `collapse` preserves the Error
  as an ordinary member of its answer expression.
- Constructive negation now applies the same declared `Atom` argument mask as
  the positive call path. `not-provable` no longer evaluates an argument that
  the function declaration says must arrive as its written atom.
- Compiled `let` now uses plain unification when it binds a value operation's
  fresh output variable. The occurs check remains on pattern/value paths that
  can share, while queue-sized bound terms no longer receive a redundant walk.
- Removing an equation from a named space now has an executable public-surface
  pin that its stored atom and module-scoped compiled clause leave together;
  the former function call becomes unreduced data immediately after removal.
- Numeric math operations now reject computed String operands at their own
  runtime doors. A one-character string can no longer cross into host
  arithmetic as its character code, including either position of binary math.
- Numeric equality now compares integer and float operands by value. In
  particular, `(== 1 1.0)` answers `True`, matching the language's grounded
  numeric equivalence rule, and `!=` uses the same rule negated.
- `add-reduct`, `git-import!`, `sleep`, and `sread` now refuse an unbound
  required input under the operation name the program wrote. Their failures
  no longer leak delegated or host predicate names; the translated `match`
  surface retains its already-aligned refusal answer.
- `(pragma! max-stack-depth N)` now caps each recursive answer branch with the
  evaluator's fuel budget. A completed sibling remains in the answer group
  when another branch reaches `StackOverflow`; zero retains the 100000-step
  default, invalid counts answer `UnsignedIntegerIsExpected`, and unsupported
  pragma names raise instead of succeeding as no-ops.
- `(get-type ())` and `(get-type-space <space> ())` report the unit type
  `(->)`, following the LeaTTa ruling. Runtime argument classification keeps
  its separate empty-expression rule. The same pinned ruling aligns `nop`'s
  rest arrow, `assert`'s unit result, and the public `is-function (->)` check.
- Type inspection treats an under-applied arrow head as an inapplicable typed
  application, not as tuple data. With `Cons : $t -> List $t -> List $t`,
  `(get-type (Cons 1))` has no answer while the fully applied constructor
  reports `List Number`.
- Reloading a variant-identical source type declaration warns and keeps the
  first row instead of storing a duplicate. A host operation may not adopt a
  hand-written declaration: that conflict names both rows and is refused.
  Public batches are preflighted as a whole, so two identical rows in one
  `add()` call publish neither copy.
- Free variables returned by runnable source now keep their written names in
  engine output and host bindings. The reader's name map travels beside each
  collected answer, so `$free` stays `$free` instead of becoming `$_0` while
  variables created after reading still use the engine fallback spelling.
  `sealed` now follows the normative ignore-list contract and returns its
  freshened Atom as data; generated variables print deterministic `#N` epochs.
- Grounded arithmetic, comparison, Boolean, numeric-math, and `format-args`
  calls whose written operands already contradict their built-in parameter
  types now report the written call before evaluating those operands. Rejected
  operands no longer perform effects, while accepted and undecided operands
  keep their existing evaluation behavior.
- A space hook consults its handler at a fixed small cost instead of
  re-translating the call on every write: 44.02 inferences per add
  against 234.03 before, beside 29.01 for an unhooked add. The handler's
  call site is translated once when the claim is made and recompiled
  automatically after any equation or declaration change.
- Removing the last equation that shadowed a builtin restores the
  builtin. The erase used to leave an empty local predicate in the
  space's execution module, which kept shadowing the engine's definition
  for the rest of the process: after removing a `car-atom` shadow from
  `&self`, every compiled caller of `car-atom` failed from then on.
  Inside a transaction the repair waits for the commit, so a failed
  reload still leaves the previous definitions standing.
- `get-atoms` with a bound pattern reads through the store's argument
  indexing instead of enumerating every clause and filtering: a
  presence probe that cost 2,055 inferences at 2,000 held atoms and
  21,055 at 10,000, linear, reads flat now, and a bound SCALAR pattern
  answers a clean miss where it used to raise a type error.
- The atom offered to a pre-add or post-add handler reaches it as itself.
  When the offered atom's head happened to name a function, the handler
  used to judge the atom's evaluation while the space received the atom,
  so the verdict was about a term that never landed. The offer is data,
  as a database BEFORE trigger's row is.

- The engine repairs its own compiled code when a function is removed, with
  no host in the process: the removal-direction recompile used to ride a
  Python clause of the `metta_on_function_removed` event, so a pure Prolog
  embedding kept a compiled mention of a retired function answering as a
  call. It is the engine's own `function_removed/1` now, on every removal
  path, and it notifies EVERY removed-event observer where one path had
  been reaching only the first. The arrival direction was never broken:
  a new function's callers flip from data to call through the load-safe
  scheduled repair registration always used, and the events are pure
  observations again.

- `eval(residuals=...)` and `AsyncMeTTa.eval(residuals=...)` no longer select
  a second return shape. A term with no applicable rule is the unreduced term
  returned by ordinary evaluation, while `eval_status()` names that path
  `not-reducible`. Undefined truth still carries its delay condition, and
  constraint stores remain inspectable inside MeTTa through `residual-goals`.

- `run()` and `eval()` now always return their list shapes. Printed output is
  collected with `with m.capture()`, while atomic, speculative, and strict
  execution use their matching `with` blocks. `register_op()` no longer has
  `typed`, `raw`, `pass_atoms`, or `pure` booleans: annotations derive type
  and evaluation-order claims, `transport="raw"` selects the raw `(op ...)`
  kind, and `declarations=` accepts lifecycle-owned `(arguments ...)`,
  `(effect ...)`, type, and other policy atoms readable through `&petta`.

- `petta.Atom` on a registered operation parameter is now documented as an
  evaluation-order contract: the callable receives the argument as written,
  while an unconstrained parameter receives its reduced value.

- Compiled definitions now carry their cleaned Python docstring through
  `Defined.doc`, `help()`, and the definition space's `get-doc` result.

- Registered operations now reflect a typed `OpDecl` for every arity and
  carry cleaned Python docstrings into their declaration space as `@doc`
  atoms. Documentation follows replacement, rollback, and unregistration.

- `register_op` now rejects coroutine, async-generator, and generator-based
  coroutine functions before registration. Its synchronous engine path cannot
  await them; ordinary generator operations remain nondeterministic.

- A Python tuple now answers as ordinary structural MeTTa data through both
  the standalone engine and Python library. Asking `py-atom` for `Grounded`
  retains a Python object reference instead of accepting Janus's eager tuple
  conversion.

- Recorded integer overflow as a deliberate host-width divergence: PeTTa and
  LeaTTa keep exact unbounded integer results where Hyperon's `i64` carrier
  answers `ArithmeticOverflow`.
- `pragma!` now refuses unknown settings and the unsupported `type-check`,
  `max-stack-depth`, and `interpreter` compatibility keys. Its accepted keys
  are limited to the two execution bounds and specialization verification,
  each of which has an active consumer. `max-time` requires a positive number,
  `max-inferences` requires a positive integer, and `none` disables either
  bound; invalid values are refused without replacing the previous setting.
- The tree partitions by seam, staging the kernel-and-satellites form.
  The engine lives in `engine/` alone; each driver seat lives under
  `bindings/` with everything it needs (`bindings/python/` carries the
  package, its decider and bridge, tests, benchmarks, tools, examples
  and the `lowerings/` seam home; `bindings/node/` is the TypeScript
  seat); each storage integration lives under `backends/` with its own
  decider and build (`backends/mork/` carries `mork_ffi`). The engine
  discovers seats and backends through two globs,
  `bindings/*/decider.pl` and `backends/*/decider.pl`, and names
  neither; `test_the_tree_partitions_by_seam` is the fence. The legacy
  `python.petta` import path still resolves to the canonical package
  through the unchanged `python/__init__.py` shim, installed wheels keep
  the same layout under `petta/_runtime/`, and `PETTA_PATH` still names
  a checkout root.
- A finite float prints the arbiter's layout over the same
  shortest-round-trip digits: `1e16`, `0.00001` and `1.5e300` where SWI's
  `number_codes/2` wrote `1.0e+16`, `1.0e-05` and `1.5e+300`. The rule is
  LeaTTa's `Decimal.formatMeTTa` (ryu's pretty layout): positional while the
  value has at most sixteen digits before the point and its magnitude is at
  least 0.0001, scientific otherwise with a bare signed exponent. Every
  spelling still reads back to the same binary64, and the reader accepted
  these forms all along, so stored sources and saves are unaffected; only
  printed text moves. No shipped example prints a float in the affected
  ranges, measured by replaying all 207 pinned corpus oracles.

- The control-signal error term is spelled `metta_control_signal(Kind,
  Detail)` and the host-interrupt signal `metta_host_interrupted`, in place
  of the `petta_py_`-spelled names: the shapes are the engine's own and
  cross every host boundary, not Python's alone. A program or tool matching
  the old spellings in raw error text must follow; the structured fields on
  the `petta.errors` classes are unchanged.

- Repeated `eval` calls reuse their compiled Prolog goal template. Templates
  are variant-keyed per execution space and are evicted when any function or
  declaration named by the source changes or is removed. Large one-shot terms
  stay uncached, and direct flat calls keep their existing fast path.

- The upstream documentation family is available with no import. `(get-doc
  $space $atom)`, `get-doc-atom`, `get-doc-single-atom`, `get-doc-function`,
  and `get-doc-params` build `@doc-formal` records from the prose and types in
  the selected space. `get-type-space` now isolates that space instead of
  merging declarations from the caller. The existing one-input `get-doc`
  continues to return the raw `(@doc ...)` atom.

- `BigInt` joins `Number` as the language's two numeric types. Floats and
  signed-i64 integers report `Number`; integers outside signed i64 report
  `BigInt`. Arithmetic still uses SWI's exact unbounded integers, so a result
  changes type when it crosses the boundary without changing value behavior.
  Existing `Number` parameters accept either integer type, while `BigInt`
  parameters remain narrow. Mixed integer equality stays exact. The catalog
  publishes `(vocabulary numeric-type Number BigInt)` and the generated Python
  surface exports the `NumericType` vocabulary class.

- The tagged wire keeps one `n` form for `Number` and `BigInt`, with the exact
  integer value selecting the language type. Python receives integers as
  unbounded `int` values through Janus. Node receives every Prolog integer as
  JavaScript `BigInt` over a decimal-text swipl-wasm bridge, so neither host
  truncates a wide value. The golden codec corpus pins both signed-i64 edges
  and arithmetic promotion.

- Lazy answers cross the wire. The remote space protocol reaches revision 3
  with an `ask`/`next`/`stop` lifecycle beside `match`, so a client takes two
  answers of a large enumeration and stops without the serving engine
  computing the rest: `/ask` opens a cursor and answers the first chunk,
  `/next` pulls the next, `/stop` releases it, and the reply's `cursor` field
  is both the continuation token and the end-of-stream signal, `null` meaning
  the server has released it already. Measured over real HTTP, two answers
  cost 1,250 inferences whether the enumeration held ten atoms or ten
  thousand, against 1,839 and 1,490,407 for the eager door over the same
  spaces.

  On the client side `RemoteSpace.stream(pattern, batch=...)` is the lazy
  door and `match()` stays the eager one, the split `m.stream()` and
  `m.query()` already make in-process, and
  `petta.remote.attach(m, "&hq", url, batch=1)` puts an attached space's
  matching on the lazy door so a MeTTa `once` over it stops the serving
  engine too. `serve()` takes `cursor_idle` and `cursor_limit`, which bound
  how long an untouched cursor survives and how many stay open at once, and
  both take their defaults from SWI's `library(pengines)`, whose
  create/ask/next/stop is the lifecycle's prior art. The TypeScript
  reference servers speak revision 3 as well, and
  `petta.testing.GatewayComplianceSuite` certifies it.

- `petta.remote.Gateway` is the protocol's server side with no transport
  under it: call it with `(operation, payload)` and it answers the reply
  dict, the shape `Transport` already has on the client side. `serve()`
  wraps one in the bundled HTTP server; mount one on the framework a
  deployment already runs, or use one as a transport directly, which is the
  one way serving and attaching join inside a single process.

- `m.lint()` reports a new kind, `subsumed-equation`: an equation that is a
  strict instance of another stored one, so every answer it gives, the
  general equation gives too, and calls on the overlap answer twice. This is
  the semantic tier above `duplicate-equation`, which keeps the exact-twin
  case. The check is Plotkin's program reduction step (1972) bounded to
  pairwise instance subsumption, and the finding says so, because the full
  test needs resolution and this one deliberately does not search redundancy
  through combinations of equations. Severity `information`.

- `SECURITY.md`, `CONTRIBUTING.md` and GitHub issue templates. The project is
  alpha and now says so: versions are `0.y.z`, every release is labelled alpha,
  and a breaking change is expected at each one, because MeTTa itself is alpha
  and an implementation of an alpha language cannot promise a stable surface it
  does not control. 1.0 waits on this repository's own surfaces settling and on
  MeTTa leaving alpha upstream, whichever comes later.

  A release is a tag on a gate-green tree and this file's newest block is its
  notes, so nothing about a release is written at release time. A vulnerability
  goes privately to the address the commits carry, with a 90-day coordinated
  disclosure window and no bounty. A contribution is an atomic pull request
  that is gate-green with its obligation headers and evidence tags in place,
  under the repository's MIT license and no contributor license agreement.

  The package metadata says the same thing to an installer that reads nothing
  else, through `Development Status :: 3 - Alpha`, and `SECURITY.md` now
  travels in the source archive beside `CHANGELOG.md` and `CITATION.cff`.

- A MeTTa source can be reloaded after you edit it, and both doors onto a file
  now mean the same thing by it. `m.load(path)` is a consult: it always loads,
  and what it loads replaces what that same file put in the space before.
  `!(import! &self path)` loads a file that is new or that has been edited, and
  skips one that is neither. The engine says on stderr which file it replaced
  and how many atoms it withdrew.

  Both used to be silently wrong, in opposite directions. A file
  `(= (answer) 1)` edited to `(= (answer) 2)` and loaded again answered `1` and
  `2` through `load`, because nothing retracted the first definition, and `1`
  through `import!`, because a second import of the same path was skipped
  outright. So one door duplicated your program and the other pretended you had
  not edited it, which between them made the fix-and-reload cycle impossible on
  MeTTa code.

  A reload is not retract-and-assert. Everything derived from the definitions
  it replaces goes with them: the specializer's clones, `memoize`'s cached
  answers, `table`'s answer tables, and any `LiveView` over the atoms that
  left. That falls out of the atoms leaving through the same removal path a
  `remove-atom` uses, which is where each of those invalidations already hangs.

  A reload that raises leaves the previous definitions standing, since the
  withdrawal and the load that follows it are one transaction. A broken edit
  costs you the error and nothing else.

  This is a behaviour change for `m.load`: loading one file twice used to leave
  two copies of its atoms and now leaves one. Loading a DIFFERENT file into the
  same space still adds to it, and atoms you put there yourself are untouched.

  `m.load` is also all or nothing now, which the engine's own door always was:
  a `timeout` or `inferences` bound that stops a load takes back everything the
  file had put in a space, rather than leaving the half it finished, because a
  file a space holds half of is not a file it can replace later. `m.run` is the
  entry point that keeps finished work when a bound stops it.
- Eight special forms are now written in MeTTa rather than in the compiler.
  `and-then`, `or-else`, `trace!`, `unique`, `alpha-unique`, `union`,
  `intersection` and `subtraction` ship as equations in the engine's prelude
  that say what the call EXPANDS TO, registered with `add-translator-rule!`.
  The expansion goes back through the ordinary translator, so one definition
  decides what the form means and the compiler carries eight heads fewer.
  Nothing about writing them changes: they are reachable with no import, they
  answer what they always answered, and a program that defines one of the
  names takes the whole form over as it always could.

  Measured over the 201 corpus examples whose inference count is
  deterministic: -0.2313% in total, 199 of them cheaper, because the six
  stream rewrites used to run on every compound the translator walked. The
  two that got dearer are the two files that write the moved forms, and all
  of it is compile time: over 200,000 `and-then` evaluations the two spellings
  cost 1,203,968 and 1,203,986 inferences, the whole difference being the
  one-time compile. Every corpus answer is unchanged, group for group.

  `KERNEL.md` is the ledger: every head the translator gives meaning to, core
  or derived, what it corresponds to in the minimal instruction set the
  arbiter presents, and for a derived form still fused into the compiler, the
  measurement that keeps it there.

- `lib/lib_derived.metta`, the derived forms the compiler keeps fused, written
  out as translator rules for a program that wants the smaller instruction set
  anyway. `once` is there: `(take 1 ...)` answers what `once` answers over all
  206 corpus files and costs 2 inferences a call more, which is why the fused
  clause is still the default. `examples/libraries/derived_forms.metta` runs
  the swap and `remove-translator-rule!` puts the compiler back in charge.

- A translator rule that does not APPLY now leaves the call to ordinary
  dispatch instead of failing the equation around it. A rule may carry a
  guard in its head, which is how `union` names the `(superpose ...)` shape it
  rewrites, and before this `(= (f) (union foo bar))` did not compile at all,
  with a message naming `process_form/4`.

- An equation head is a PATTERN at every depth, matched structurally. A head
  argument whose label happened to have equations used to become a CALL, so
  `(= (f (g $x)) $x)` compiled to `f(A, B) :- g(B, A)` and ran `g` backwards.
  That made the reading invisible, since nothing in the source said which
  positions were calls; order-dependent, since defining `g` after writing the
  head changed how the head compiled; and silent when it went wrong.

  The mechanised semantics has one matching relation. `AST.matchPat` says "a
  pattern variable matches any subterm (and must match consistently if it
  recurs); constructors match structurally; everything else matches only
  itself", four cases with no case reading whether a label is defined, and an
  equation is applied by matching its whole left-hand side. Two of the
  arbiter's own cases decide it and this engine failed both:
  `(= (outer-hold (inner-sum $x $y)) outer-held)` with an `Atom` parameter
  answers `outer-held` there and RAISED here, and
  `(= (nested-atom (produce-pa3)) held)` beside `(= (nested-atom pa3) ...)`
  answers only the second there and answered BOTH here.

  The relational reading is not lost, it moves to where it runs. `(= (h
  (myfunc (10) $B) $C) ($B $C))` becomes `(= (h $A $C) (let $A (myfunc (10)
  $B) ($B $C)))`, which unifies the argument with what the call produces and
  answers exactly the same answers. `examples/functions/functionhead.metta`
  and its two successors, `examples/libraries/patrick_test.metta` and
  `examples/reasoning/tilepuzzle.metta` are written that way now, and the
  204-example corpus answers identically, group for group. An equation whose
  head relied on evaluation must make the same move.

- `(case Key Cases)` reads a case pair that is still a variable as a pair
  that has not arrived, the way it already read a cases list that is still a
  variable. The rewrite used to unify its own `(pattern value)` shape INTO
  such a pair, so `(= (f $p) (case 1 ($p)))` compiled to a head demanding a
  two-element list instead of the head the program wrote, and an argument
  that was not one failed silently. It compiles to the same runtime path the
  rest of the form already uses, so the pair is a branch when it arrives and
  a value that is not a pair is refused naming the form.

- `(let* Bindings Body)` no longer drops its bindings when they are not
  written out. The form rewrites bindings it reads as syntax into nested
  `let`s, and a bindings argument that is still a variable has none to read:
  it used to unify with the empty list under the rewrite's own cut, so
  `(= (mylet $bs $b) (let* $bs $b))` compiled to `mylet([], A, A)` and every
  binding a caller wrote was lost without a word. A pair that is still a
  variable was the same defect one level in, where the rewrite unified its
  own `(pattern value)` shape INTO the source and `(= (letpair $b) (let* ($b)
  99))` compiled to a head demanding a two-element list.

  Bindings that are not syntax now compile when their value arrives, through
  the same rewrite the written-out form uses, so `let*` under another name is
  an ordinary definition. A value arriving there that is not a list of
  `(pattern value)` pairs is refused naming the form and printing the
  argument as MeTTa: `let*: a list of (pattern value) bindings expected,
  found $_0`. Bindings that are no list at all, `(let* foo ok)`, keep falling
  through to the unapplied form as before.

  `(not-provable ...)` over such a form refuses too, and used to answer from
  a dual with the bindings dropped. A dual is built once, out of the equation
  as it was written, so bindings that only arrive when the program runs have
  none to expand. Writing them out gives the form a dual, as it always did.

  Measured cost: writing the bindings out is unaffected, the 203-example
  corpus answering identically group for group, and a flat 3 inferences a
  call at 2 and at 16 bindings; handing them over costs one rewrite and
  translation per call, 62 and 370 inferences for the same two sizes. A
  `let*` on a hot path is worth writing out.
  `examples/control/letstarcomputed.metta` runs all of it.

- A conjunctive `match` now finds every row before any output template runs,
  which the language specifies: "match first finds all the matches, and then
  instantiates the output pattern with them, which is evaluated outside match.
  If `remove-atom` and `add-atom` would be executed right away for each found
  matching, the condition of circular links would be broken after the first
  rewrite." On the doc's own graph-rewriting example, upstream reverses all
  three links of a loop and this reversed ONE, the first template's
  `remove-atom` breaking the cycle for every conjunct that had not run yet.

  A single pattern always had the guarantee and still streams: it is one goal
  over one dynamic predicate, and Prolog's logical update view already fixes
  what it sees at the call, so `(once (match &big (foo $x) $x))` does not walk
  a big space. A conjunction is where that ran out, because each later conjunct
  is a fresh goal started after the previous row's template wrote. Its rows are
  now collected first, annotations included.

  `examples/spaces/match_snapshot.metta` runs the doc's example and the
  arbiter's own two-row detector under the gate.

- Clearing a space now empties both of its halves. A space has stored atoms
  and, for the atoms that compiled, clauses in its own execution module, and
  the engine's own clear dropped only the first: define
  `(= (past-life) inherited)` in a space, clear it, and `!(past-life)` in that
  now-empty space still answered `inherited`. Space names are pooled, so that
  is a previous life answering through a recycled name.

  The Python surface was never affected, because its clear removes equations
  through the removal path before reaching the engine door. Every other caller
  got the half clear, and the reload path will come through the same door.
  Equations and type declarations now leave through `metta_remove_atom/3`,
  which un-compiles the clause and forgets the function name when nothing else
  defines it; plain atoms have no compiled half and stay on the one-retractall
  sweep.

- `remove-atom` takes ONE occurrence, not every one. A space is a multiset and
  removal is multiset subtraction, so three `(add-atom &self (dup 1))` and one
  `(remove-atom &self (dup 1))` now leave two; they used to leave none. The
  same holds for a pattern: `(remove-atom &self (edge a $any))` takes one of
  the atoms unifying with it, and `del m[pattern]` is the bulk spelling that
  drains them all.

  The old reading's stated reason argued for the opposite of what it
  concluded, "a MeTTa space is a multiset unless something forbids it, SO
  removal takes EVERY occurrence", and the tree it produced was a multiset on
  add and a set on remove. The arbiter reads the premise the other way:
  `remove-atom` "must behave as multiset subtraction on the reader-visible
  view of `&self`", and its own model "removes the first exact occurrence and
  returns unit". This engine had already decided it everywhere else, in the
  seam's own `metta_foreign_remove/3` ("remove one") and in the retained
  equations, which go one variant-equivalent clause at a time.

  One law now, whichever space holds the atoms. `PersistentFactSpace` retracts
  one journalled fact instead of a `retractall` sweep, so its journal records
  `retract(Fact)`; the TypeScript reference servers, the C store example, the
  CeTTa and DuckDB example providers and the remote protocol's conformance
  suite all subtract one. `LiveView` mirrors it: a removal event carries the
  pattern that was asked for rather than the occurrence that left, so a ground
  removal decrements locally and a pattern removal re-reads the space rather
  than guessing which copy went.

- `remove-atom` distinguishes a removal that happened from one that found
  nothing. Removing an atom the space holds still answers the unit value;
  removing one it does not hold now answers
  `(Error (remove-atom <space> <atom>) "remove-atom: atom is not in the
  space")` instead of the same silent unit.

  The language's own text is what asks for this. "If the given atom is not in
  the space, `remove-atom` currently neither raises a error nor returns the
  empty result" is a complaint, and upstream carries the same question
  unanswered as a TODO at `stdlib/space.rs:219`, "Is it necessary to
  distinguish whether the atom was removed or not?". The arbiter answers it:
  LeaTTa's Hyperon-Hacks-Register row 15 rules "Implement. Keep the
  distinction", and `Metta.Minimal.removeAtomStep` is where it holds. This is
  a deliberate divergence from Hyperon as shipped, which answers unit for
  both, towards the specification the two of them share.

  The refusal is an answer and not a throw, so `(collapse (remove-atom ...))`
  holds it and a program can branch on it. `metta_remove_atom/3` still answers
  the plain boolean the engine's own callers read.

- `get-atoms` and `match` refuse a first argument that is not a space by
  answering a MeTTa error naming themselves, the way `add-atom` already did.
  Both used to raise SWI's bare `Arguments are not sufficiently instantiated`,
  which names neither the operation nor the call, aborts the whole file under
  `run.sh` and arrives in Python as an `EngineError` whose `operation` field
  is `None`. Now `!(get-atoms $u)` answers
  `(Error (get-atoms $u) "get-atoms expects a space as its argument")` and
  `!(match $u (foo $x) $x)` answers
  `(Error (match $u (foo $x) $x) "match expects a space as the first
  argument")`, both as data a `collapse` can hold rather than as a throw that
  would empty it. The wording follows upstream, which words the one-argument
  operation differently from the two-argument ones: pinned `space.rs:143` says
  "its argument" where `:172` and `:199` say "the first argument".

  The refusal reaches the conjunctive form too, `!(match $u (, (foo $x)
  (bar $x)) $x)`, which used to commit to the conjunction router before the
  space was ever examined.

- Every space now compiles its equations into a Prolog module of its own,
  `&self` included, and `space_module/2` names it. `&self` used to compile
  into the module the engine's own predicates are in, so an equation whose
  head collided with one of them did not shadow that predicate, it REPLACED
  it for the rest of the process. Two shipped examples did exactly that:
  `examples/functions/invertpeanoplus.metta` defines `(= (plus Z $y) $y)` and
  took the engine's `plus/3` from imported to a local definition, after which
  `plus(1,2,X)` failed instead of answering `3`, and
  `examples/libraries/minimal_metta.metta` did the same to `rule/3`. Sharper
  still, `!(add-atom &self (= (b_setval $a) clash))` used to leave
  `with_metta_module/2` unable to run, so the very next MeTTa form failed to
  translate.

  What a program can do changes with it, and in the direction of MORE names
  rather than fewer. An equation for a builtin's name in `&self` is accepted
  and shadows it for `&self` alone, exactly as it already did in a named
  space; the engine's own predicate of that name goes on answering. What is
  still refused is SWI's protected core, and it is refused in every space
  rather than in `&self` alone: measured 2026-08-19 through the shipped
  guard itself, 8 of the 463 imported names at MeTTa arity 0, 4 at arity 1,
  3 at arity 2 and 2 at arity 3, against 91, 232, 173 and 66 of 458 before.
  The four still taken at arity 1 are `call`, `clause`, `copy_term` and
  `sort`.

  For extension authors: `user` is the HOST module and nothing else now. Keep
  consulting Prolog into it, ask `space_module/2` for a space's module, and
  pass THAT to `with_metta_module/2`, which refuses a space name rather than
  running your goal against a module nothing compiles into. `EXTENDING.md`
  carries the whole rule.

  `tests/prolog/engine_integrity.pl` is a GATE at zero findings and reports
  again the day a space's module lands back on the engine's resolution path.

  Measured cost: `space_module/2` 4.00 inferences against 3.00 and
  `with_metta_module/2` 11.00 against 10.00, so a runnable form is 372
  against 369. Eleven counter baselines are raised with that attribution and
  no other number moved.

- A builtin handed an unbound variable where it needs a value now says so, by
  name. Measured 2026-08-19 by a probe generated over every position the
  engine's own type surface declares strict, this failed four different ways
  at once: 28 positions BOUND THE CALLER'S VARIABLE, `!(car-atom $u)`
  unifying `$u` with `[H|_]` through the clause head and answering the fresh
  head; 13 answered a fresh variable and 12 an answer derived from nothing,
  `!(union-atom (a b) $u)` giving the partial expression `(a b|_)`; 2
  EXHAUSTED THE STACK, `!(subtraction-atom $u (a b))` walking a list with both
  ends open; and 7 raised naming a Prolog predicate the program never wrote,
  `!(sort-atom $u)` saying `msort/2` and `!(sread $u)` saying `atom_codes/2`.

  83 positions refuse now, each reading like
  `car-atom: a value expected in argument 1, found an unbound variable`. The
  table is derived from `builtin_type_declaration/2` rather than listed, so
  declaring a type for a new builtin guards it in the same stroke, and the
  probe in `tests/prolog/metta.plt` walks the same table. It costs nothing
  where it would be felt: `car-atom` on a real expression is 2.0000
  inferences per call with the guard and 2.0000 without, over 200,000 calls.

  What stays relational is named rather than left to be discovered:
  `(index-atom (a b) $i)` enumerates, `and`, `or`, `not`, `xor` and `implies`
  enumerate the truth table, `cons` builds a pattern with an open tail, which
  the engine's own prelude writes as `(cons Error $_)`, `union-atom` and
  `member` are `append/3` and `member/2` under MeTTa names and a shipped
  library splits a list with the first, and the `#` constraint family is
  relational throughout. A name lent to MeTTa from SWI, `msort`, `append`,
  `sort`, `maplist`, `length`, keeps Prolog's own behaviour, because under
  that name it IS the Prolog predicate.

  It costs `let-heavy` 3.35%, 5,054,208,356 instructions against 4,890,210,090
  without it, and that difference is the guard on `car-atom` alone.
  Measured 2026-08-19, min of three, spread under 0.001%: an INERT extra
  clause on `car-atom` costs 3.13% by itself, an SSU rewrite 3.51%, and an
  unrelated inert predicate of the same size in the same place costs 0.00%,
  which rules out code layout. The inference count is 2.0000 per call either
  way, so the engine's own counter cannot see it: it is SWI's clause
  selection. No arrangement avoids it, and the alternative is
  `!(car-atom $u)` going on binding the caller's variable, so the counter is
  rebaselined with this attribution and no other number moved.

  Six positions are NOT covered and the engine says which:
  `unguarded_input_position/2` names `get-atoms`, `match` and `add-reduct` in
  `engine/spaces.pl`, `sread` in `engine/parser.pl`, and `git-import!` and `sleep`
  in libraries, each in a file this change does not own. A test asserts they
  are still uncovered, so the day one is fixed the row comes out instead of
  the gap going quiet.

- `==` and `!=` refuse a comparison across two KNOWN and different types
  instead of answering `False`. `!(== 1 "S")` answered `False`, which is also
  the answer for two Numbers that differ, so a conditional took the else
  branch and nothing said the question was meaningless. Both are declared
  `(-> $a $a Bool)` now, one type variable, matching upstream's own signature
  for `==`, and the refusal names the operation and the operand:
  `==: Number expected, found "S"`.

  Only a PROVEN mismatch is refused. `!(== 1 a)` still answers `False` when
  nothing declares `a`, because nothing is contradicted, and expressions are
  left alone entirely: `!(== (collapse ...) ())` and `!(== (1 2 3) ())` answer
  exactly as before. `=alpha` is unchanged and remains the comparison that
  takes anything, so a program that wants a cross-kind verdict has one.

  Measured 2026-08-19 on hyperon 0.2.10 and on the LeaTTa mechanised
  interpreter over 29 shapes; every shape the two references agree on now
  matches, and the three they disagree on keep the answer PeTTa already gave.
  Costs nothing on the hot path: a thousand-iteration `==` loop is 4487.45
  inferences before and after, because two numbers are settled inline.

- `%Undefined%` is the gradual type and is now consistent with every type in
  both directions, which is what decides whether a typed call admits an
  argument. This engine had both directions backwards. A parameter declared
  `%Undefined%` demanded that the argument be UNTYPED, so
  `(: tensor (-> %Undefined% DLTensor))` refused `1.0` and
  `!(get-type (tensor (1.0)))` answered `((-> %Undefined% DLTensor) (Number))`
  instead of `DLTensor`; and an argument nothing declares failed a concrete
  parameter, so a typo'd symbol was refused where both references accept it.

  A call site refuses only a PROVEN conflict now: with
  `(: f (-> Number Atom))`, `!(f "s")` is still refused and `!(f undeclared)`
  answers. What does NOT change is a contract, because a contract asks the
  other question: `(admits &pool Space)` still demands a witness, since an
  atom nothing declares is not evidence of a Space.

  Measured 2026-08-19 on hyperon 0.2.10 and on the LeaTTa mechanised
  interpreter, byte-identical across both, over concrete, metatype and `Bool`
  parameters. Three shipped tests asserted the stricter rule and were
  corrected against that measurement.

- An expression no arrow types is read element-wise, and the tuple it reads is
  now `%Undefined%` as soon as one member's type is. Nothing is known about a
  tuple one of whose components is unknown, so reporting the shape while a
  hole sits inside it claimed more than had been derived:
  `!(get-type (some-undeclared-call))` answered `(%Undefined%)`, a one-element
  tuple, where the answer is that nothing is known at all. A fully typed
  expression is unaffected, so `(typed-sym typed-sym)` is still
  `(Number Number)`. The collapse is recursive because the walk is bottom-up:
  an inner tuple carrying a hole makes the outer one `%Undefined%` too.

  Measured 2026-08-19 on hyperon 0.2.10 and on the LeaTTa mechanised
  interpreter, byte-identical across both, over fourteen shapes.

- `(transaction ...)` answers everything its body answers. It used to answer
  the first one only and say nothing: `!(collapse (petta-three))` with three
  equations for the name answered `(1 2 3)` and
  `!(collapse (transaction (petta-three)))` answered `(1)`, because SWI's
  `transaction/1` runs its goal as `once/1`. Dropping answers is an opacity
  violation in the transactional-memory sense, since a reader of the result
  sees a state no serial run of the body produces.

  The form collects its body's answers inside the transaction, commits, and
  replays them after, so the atomicity is unchanged and now covers the whole
  answer set: every answer's writes land together, a body that ends with no
  answer rolls all of them back and fails, and one that raises rolls all of
  them back and re-raises. Refusing a nondeterministic body was the other
  option and it is not cheaper: knowing a Prolog goal is nondeterministic
  means running it to a second answer, at which point the answers are in hand
  and refusing them throws away work already done.

  The cost is that the answers are materialized. A body with an unbounded
  answer set now exhausts the stack and raises where it used to yield once,
  which is the honest price of atomicity over a whole answer set. Measured
  2026-08-19 over a three-answer body: 557.04 inferences plain against 773.05
  through `transaction`.

- `get-type` and `get-type-space` no longer run the expression they are asked
  about. Asking for a type is a question about an expression, and the engine
  was answering it by running the expression first: an operation appending to
  a Python list fired on `!(get-type (petta-effectful))`, taking a counter
  from 0 to 1, and the answer was `Number`, the type of what it returned.
  Every linter walk and every REPL inspection was invisibly effectful on a
  seam whose whole purpose is arbitrary effects.

  What changes for a program: `(get-type EXPR)` now answers what `EXPR` is
  DECLARED to be, not what running it would produce. A declared function
  answers its return type, `!(get-type (literal-return 2))` being `Atom` for
  `(: literal-return (-> Number Atom))`; a builtin application answers its
  arrow's return type, `!(get-type (+ 1 2))` being `Number`; and an
  application of a name nothing declares answers `%Undefined%` where it used
  to answer the type of the value the call produced. To ask about a VALUE,
  produce it first: `!(let $v (f 1) (get-type $v))`.

  Measured 2026-08-19 on hyperon 0.2.10 and on the LeaTTa mechanised
  interpreter, byte-identical across both, over seven probes: the effectful
  argument does not fire on either, and each of the four answers above is
  what both of them give.

- `(case Key Cases)` no longer allocates 7.5 Gb and dies when its cases are
  not written out. The form compiles one nested conditional from cases it
  reads as syntax, and a cases argument that is still a variable has none to
  read: it used to reach a `select/3` over an open list, which enumerates
  longer and longer instances of that list forever. `!(case 1 $cases)` did it
  bare, under `once` and under `collapse` alike, and so did merely LOADING
  the one-line definition `(= (switch $v $cs) (case $v $cs))` that gives
  `case` another name.

  Cases that are not syntax now compile when their value arrives, through the
  same code the written-out form compiles through, so a `switch` written as
  an ordinary definition loads and answers. A value arriving there that is
  not a list of `(pattern value)` pairs is refused naming the form and
  printing the argument as MeTTa: `case: a list of (pattern value) cases
  expected, found $_0`. Cases that are no list at all, `(case 1 foo)`, keep
  falling through to data dispatch as before.

  Measured cost: writing the cases out is unaffected, byte-identical compiled
  goals over twelve case shapes and a flat 3 inferences a call at 3, 12 and 24
  cases; handing them over as a value costs one translation per call, 78, 258
  and 498 inferences for the same three sizes. A `case` on a hot path is
  worth writing out. `examples/control/casecomputed.metta` runs all of it.

- `(atomically EXPR)`, the atomic block under the name the concurrency
  vocabulary uses for it: Haskell's STM spells it `atomically`, Clojure's
  spells it `dosync`, and PeTTa's `transaction` is the same operation under
  the database name. It did not exist, so `!(atomically (+ 1 1))` answered
  `(atomically 2)`, an unknown head applied to its evaluated argument, rather
  than running anything atomically.

  It is sugar over `(transaction ...)`, deliberately, so the two cannot
  drift: every guarantee is `transaction`'s, answer preservation and
  whole-answer-set commit-or-rollback included, and there is one
  implementation of them.

  They are still not one operation wearing two names. `transaction` is a
  special form and compiles its body into the call site, so the body has to
  be written there and `(let $b <a term> (transaction $b))` answers the term
  unrun. `atomically` takes its body as an unreduced atom and evaluates it,
  so the body may be a term the program computed. Measured 2026-08-19 over a
  three-answer body: 773.05 inferences through `transaction` against 956.07
  through `atomically`, which is what evaluating a runtime term costs against
  compiling the body in place.

- `(super (f a b))`, the relative way to reach the definition a space's own
  equation shadows. A space can redefine a function it inherits, and until now
  an override was replace-or-nothing: a guard that wanted to check a call and
  then let it through had no way through. `super` names the next definition up
  the space's own chain, so the guard delegates without naming its target, and
  the target includes the ENGINE's own definitions, so a builtin can be
  wrapped rather than only replaced.

  ```metta
  (= (store $atom) (stored $atom))
  !(bind! &guarded (new-space))
  !(add-atom &guarded (= (store $atom)
                         (if (== $atom bad) refused (super (store $atom)))))
  !(evalc (store good) &guarded)   ; (stored good)
  !(evalc (store bad) &guarded)    ; refused
  ```

  `evalc` is the other direction and both are worth having: it names the space
  to evaluate in, absolutely, where `super` names the next definition along,
  relatively. Absolute addressing does not compose. Two guards on one name,
  each delegating to the same named space, both run, and an atom the first
  refuses is stored anyway by the second, because neither of them names the
  other.

  The target is resolved when the equation COMPILES, so it costs nothing at
  the call and nothing above to reach is an error where the equation is
  written rather than a silent empty answer where it runs. A space that later
  gains a definition of the name becomes the nearer target, and the callers
  are rebuilt when it does. `examples/spaces/super.metta` runs all of it.

- The LeaTTa conformance lane (`tests/conformance/leatta.py`) now gates PER
  AREA instead of all-or-nothing. `--gate-areas-file PATH` reads a plain
  list of LeaTTa `tests/semantics/` area names, one per line: an area it
  names must have zero differing checkable files right now, and a later
  regression there fails the run the same way every other GATE line in
  `check.sh` does. An area it does not name still runs on every call, still
  prints every difference in full, and can never fail the run by itself.
  Promoting an area is now a one-line data change,
  `tests/conformance/leatta_gated_areas.txt`, not a code change.

  Measured 2026-08-18 against all 301 files across the nine areas: none
  qualifies yet. control-stdlib 2/13, eval-core 7/27, grounded 1/36,
  matching 7/11, metaprogramming 1/9, modules 0/28, spaces 0/17,
  types-basic 28/75, types-meta 4/20 checkable files agree, so the shipped
  gate-areas file lists all nine as comments and promotes none of them.

  `tests/conformance/leatta_gate_selftest.py` proves the mechanism itself
  discriminates, against a small fixture corpus rather than LeaTTa's own: a
  promoted area's regression fails the run and is named in the failure; an
  unpromoted area's identical regression prints in full but never fails the
  run. It needed a fixture because none of LeaTTa's nine real areas is
  clean enough yet to demonstrate the "a currently clean area regresses"
  half against.

- The example corpus now runs through BOTH configurations, the engine alone
  and the shipped Python library, and `bindings/python/tools/example_parity.py`
  requires them to agree. Until this lane existed the corpus only ever ran
  through the engine: the `examples` gate invokes `swipl` on `engine/main.pl`,
  `test.sh` and `test_metta_examples.py` shell to `run.sh`, and the plunit
  suites load `engine/metta.pl` without `bindings/python/petta/shim.pl`. So the
  configuration users ship was gated by unit tests alone, and defects lived
  there under green lanes.

  It found seven within the hour, all one root: `run()` and `load()` did not
  register a source's function signatures before processing its forms the way
  `engine/filereader.pl` does, so a `!` naming a function defined LOWER DOWN in
  the same file failed in the library and succeeded in the engine. Six
  `test_memo_*` examples and `newtons_method.metta` are written that way.
  They pass now, both paths sharing `prepare_parsed_forms/1`, and the lane is
  a GATE [measured 2026-08-18: 200/200 agree].

  It reads the engine through `tests/conformance/leatta_run.pl`, which
  already existed to print one answer GROUP per runnable form, and compares
  the groups as VALUES rather than as text. Both matter and both were got
  wrong first. Comparing flat lines could not tell `!(superpose (1 2 3))`
  then `!(+ 1 1)` from `!(superpose (1 2))` then `!(superpose (3 2))`,
  since both emit the answers 1 2 3 2; that file's own header says why the
  grouping is the observation. And comparing text reported the engine's
  `true` against the library's `True` on 191 of 200 files, which is a
  spelling and not an answer: both parse to `Gnd(True)`.

- `tests/example_skips.txt`, the one definition of which examples a runner
  does not run, each with its reason. There were four: six basenames in
  `test.sh`, six in `bench.sh`, seven in `check.sh`, and all of them
  matched on basename, which silently skips any future example sharing a
  name with one of these. `check.sh`'s seventh entry never matched
  anything: it named a file under `_fixtures/`, which the runners' own
  `find` excludes before any skip is consulted.

  `test.sh` and `check.sh` now match on PATH; `bench.sh` still derives
  basenames from the same file, and that difference is real rather than an
  oversight, because it compares against an upstream base whose examples
  are flat where this tree groups them into folders.

- `MeTTa.load()` and `AsyncMeTTa.load()` take `timeout=` and `inferences=`,
  the pair twelve sibling entry points already took. `load` is the one most
  likely to be handed code the caller did not write, since a file carries
  `!` directives and an import graph, and it was the one with no bound at
  all. Both go through the engine's own guards, so they raise
  `TimeLimitError` and `InferenceLimitError` like every other bounded call,
  and whatever the file completed before the stop stands.

- `MeTTa.subscribe()` takes `queue_max=`, and `petta.SubscriberError` is
  exported.

- The reader separates atoms on every Unicode whitespace character now, not
  on seven ASCII ones. 21 of the 25 characters carrying the Unicode
  `White_Space` property left `(1<sep>2)` a single symbol, so
  `!(superpose (1<sep>2))` answered one atom where it should answer two, and
  it did so silently rather than as an error. NO-BREAK SPACE is the one that
  arrives by the most ordinary route there is, since it is what HTML's
  `&nbsp;` renders to: `(foo bar)` pasted out of a browser became one symbol,
  matched nothing, and reported no problem. The file loader and `sread/2`
  also disagreed about the same question, so
  `(= (a) 1)<IDEOGRAPHIC SPACE>(= (b) 2)` loaded while the same file written
  with a NO-BREAK SPACE raised `expected '(' or '!('`.

  One table, `metta_token_boundary/2`, says where a token ends, and the
  layout skipper, the token scanner, the number terminator, the console's
  incomplete-line test and the file loader all read it. It is upstream
  MeTTa's own rule, a word ending at `c.is_whitespace()`, `(`, `)` or `;`.
  The class no longer moves with the locale either. `code_type/2` follows the
  C library, which answers 21 characters under a UTF-8 locale and 6 under
  `LC_ALL=C`, so a leading IDEOGRAPHIC SPACE used to parse under one and
  raise under the other.

  What a program can do changes with it. A symbol whose name holds whitespace
  has no text spelling that reads back as itself, so `save()` and the text
  seam refuse it now rather than writing a dump that reads back one atom
  short. Reading the shipped corpus while asking `metta_unwritable_symbol/2`
  about every form also got cheaper, 22.06M inferences against 24.30M and
  13.01G instructions:u against 18.38G, min of 3 interleaved runs.

- Copying a space now answers a space that holds what its source holds.
  `copy()` enumerates a space and re-adds every atom into a fresh one, and a
  specialization is stored content, so the clone re-derived the specialization
  while compiling the equation that triggers it and the copied one landed on
  top: a four-atom space cloned to six and answered its query three times
  instead of once. The specializer owns the names it generates, so an equation
  arriving for a name a space's module already derived carries nothing new and
  is not stored again. `digest()` agrees across a copy for the first time.

- A function's retained equations now belong to the module that compiled
  them, so a definition in one space can no longer add answers to another.
  The specializer reads those equations to build a specialized clause, one
  clause per equation, and they were held in a table keyed by function NAME
  alone: two spaces each holding `(= (my-map $f $x) ($f $x))`, the second
  compiling `(= (my-use $z) (my-map my-inc $z))`, and that space answered
  `(my-use 1)` TWICE, once per equation in the shared pile. It is older than
  the module migration, measured the same way at `c7126f1`. A space still
  sees the equations of the spaces above it, because the read follows its
  own module chain and stops at the first module that has them, which is how
  Prolog resolves the clauses those equations became.

  Measured cost: 4.00 inferences per compiled call site, paid while the
  translator builds the site rather than when the call runs, so seven
  counter baselines and one instruction floor are raised with that
  attribution and nothing at run time moved.
- Subscription dispatch goes through the discrimination tree this package
  already ships instead of unifying the atom against every subscription on
  the space. `MatchIndex` was referenced only by its own tests and one
  benchmark, while its docstring names pub/sub topic matching first and the
  write path ran the linear scan.

  Measured 2026-08-19, 1000 standing queries on one space and 200 writes
  with exactly one subscription matching each, controlled `instructions:u`,
  minimum of three: **4,012,009,981 scanning against 48,243,634 indexed,
  83.2x**. Both delivered 200 of 200, so that is the same work done two
  ways. Stated honestly, the scan already filtered by space and by `on`, so
  N was per-space and a program with ten subscriptions gains little; this is
  the many-subscriptions case, not every program.

  Delivery ORDER is part of the contract, because delivery is synchronous
  and inside the write, so two subscribers on one atom compose in the order
  they were registered. Routing through the tree changed that order before
  two defects in `MatchIndex` itself were fixed, and every subscriber still
  fired, which is what makes it worth a test of its own:

  - its entry ids were `(id(atom), live entry count)`, and the count goes
    back DOWN on remove, so a later registration took a number a survivor
    already held and the two then sorted by whichever the tree walk reached
    first. Measured: register a, b; remove a; register c; the answer came
    back c before b. The id half was no help either, since CPython reuses an
    address as soon as the object at it is freed. Ids are now a counter that
    only goes up.
  - a NaN token was looked up as a dict key, and a NaN is not equal to a
    different NaN, so two atoms the kernel calls equal took different edges
    and one was never retrieved. Measured: two distinct `float("nan")`
    values, the tree answered nothing where `unify` answered a match. This
    broke `MatchIndex`'s own documented guarantee that it agrees with brute
    force.

  A probe carrying variables goes down the registration list instead, which
  is a shape the write path meets: `(rule $x)` is a real atom to store and
  reads back as `(rule $_608)`. The tree reads probe tokens literally, so a
  variable there would need every edge followed at once.

  `subscription-dispatch` joins the benchmark lane with its A/B in the
  baseline comment.

- A subscription's event queue is bounded. `Subscription._queue` was a plain
  list, so a no-callback subscription that nobody drains grew for the life
  of the process: measured 2000 events queued after 2000 adds, at roughly
  152 bytes an Event.

  A full queue REFUSES the event rather than discarding the oldest.
  `collections.deque(maxlen=N)` is the stdlib bound and the wrong one here,
  because a silently shortened history is how a stalled consumer stays
  hidden; `queue.Queue` is the right precedent, where `put_nowait` on a full
  queue raises `queue.Full`. The refusal arrives as `SubscriberError`,
  because the write it interrupts still stands.

  The async stream is bounded the same way, and cannot refuse a write
  because by the time it runs the write has returned: it delivers every
  event that fit and then ends by raising, naming how many it could not
  take. Losing them without saying so was the only other option.

- The `S.foo` and `V.x` cache is an LRU rather than a FIFO. It returned on a
  hit without touching the cache, so `del cache[next(iter(cache))]` evicted
  by insertion age: a name used on every line aged out on the same schedule
  as one used once, and the header's promise that "repeated recent names
  preserve identity" was not true of it. `_atoms_core._wire_intern` in the
  same package already had the correct version, two tiers taken from
  CPython's own `re` module cache, so this copies it: an LRU main tier with
  a small fast tier in front that keeps the hit lock-free and
  reorder-free.

  Simulated 2026-08-19 at the shipped size of 512, a small hot set
  interleaved with fresh names: 82.4% FIFO against 88.4% LRU at 200 hot
  names, 70.4% against 82.4% at 400. Over 2048 touches of one hot name,
  insertion-age eviction re-minted it five times where two tiers minted it
  once.

- A watcher that raises now reaches the writer as `SubscriberError`, which a
  refused write never is. A subscription callback runs inside the write that
  triggered it, so its exception comes back out through the writer, and
  measured 2026-08-19 both of these arrived as `EngineError: Python
  '<Type>': <text>`, the same class and the same message template: a
  provider refusing the write, with nothing stored, and a watcher failing
  after the write landed, with the atom stored. The two call for opposite
  responses. Retrying a refused write is right; retrying an applied one took
  the count from 1 to 2 and left it there, because a space is a multiset and
  no later write undoes the copy.

  `SubscriberError` carries `subscription`, the standing query whose
  callback raised, `atom` and `space`, `action` as `"add"` or `"remove"`,
  and `__cause__`, which is what the callback actually raised. Its message
  says the write was applied and names the one thing that undoes it, an
  enclosing atomic run or `(transaction ...)` scope, which rolls it back as
  the error leaves the scope. It is a `PettaError`, so nothing that caught
  these before stops doing so.

  A rehydrated `PettaError` now keeps the `__cause__` it was raised with
  instead of having it replaced by the Prolog term it crossed. The boundary
  is still reachable as `__context__`; what changed is that the diagnosis is
  no longer displaced by the plumbing.

- `RemoteSpace` no longer claims the `subscribe` capability. `SpaceProvider`
  derives it from `add` plus `remove`, which is exact for a space whose every
  change goes through this process, because the engine's own write hooks are
  then the event source. A remote space is the one shape where that inference
  fails: its contents change on the server, which is the whole reason it is
  remote, and the wire has four operations, `match`, `enumerate`, `add` and
  `remove`, none of which carries an event.

  Measured 2026-08-19 against an attached space: a subscription was accepted,
  delivered the one atom this process wrote, and delivered nothing at all for
  the atom the server added. So a watcher heard only the changes it had
  already made itself, which is the one set it did not need to be told about.

  The capability is now refused with a sentence naming what is missing and
  the two routes that do work: poll `match()`, or run the subscription on the
  engine that owns the space and `bridge()` the changes across, which needs
  only `add` and `remove` on this side. Everything the wire does carry is
  unaffected.

- A persistent journal torn mid-record now recovers from every point it can
  be torn at, rather than from most of them. `library(persistency)` writes
  one action and its newline in a single call, so a file ending without that
  newline ended inside the write, and which byte it stopped at is chosen by
  the crash. The classifier asked `read_term_from_atom/3` whether the
  leftover bytes were a whole term, and that predicate does not require a
  terminating full stop: its documentation says "It is not required for Atom
  to end with a full-stop". So every prefix of the action name `assert`,
  from one letter to six, read as a complete Prolog atom, and
  `assert(edge(a,b))` read as a complete term, and each of those seven torn
  journals was refused with
  "ends with a complete but invalid record" for an operator to repair by
  hand. Measured 2026-08-19: 7 of the 18 truncation points of
  `assert(edge(a,b)).`

  The terminating full stop is what separates a finished record from a torn
  one, so the classifier now asks the reader that demands one, `read_term/2`
  over a string stream. A tail that still carries its full stop is refused
  exactly as before, because only its newline was lost and truncating would
  throw away a record the writer finished.

- A nondeterministic Python operation's answer stream is now closed by the
  code that consumed it, instead of being left to the garbage collector.
  The stream is one-shot and can hold a file, a database cursor or a lock
  open between yields, and a MeTTa program abandons it constantly: `once`
  cuts, a `timeout=` or `inferences=` guard stops mid-answer, an exception
  unwinds.

  The release itself was already happening, through CPython's reference
  counting, at every abandonment shape measured on 2026-08-19 with the
  cycle collector switched off. What was not happening is being told when
  it FAILS. A generator whose `finally` raises while letting go of its
  resource had that exception swallowed by the deallocator, which prints
  `Exception ignored while closing generator` to stderr and lets the call
  answer normally, so a cursor that could not be released told nobody.
  Closing the stream in `dispatch_many`, `dispatch_raw_many` and the
  inverse path puts the failure back in front of whoever abandoned it.

  PEP 533 is the reason not to keep relying on the collector even where it
  works: on an implementation that does not reference-count, "calls to
  `__del__` may be arbitrarily delayed".

- The engine and its libraries now declare every import they actually use,
  instead of getting several of them from SWI's autoloader by accident.
  `set_prolog_flag(autoload, false)` is Phase 11's precondition, because a
  system-based module gets library predicates from autoload rather than
  from `user`, so an incomplete export list would still be green under
  autoload and that is exactly the "modular errors slip in silently"
  failure the migration exists to prevent. Turning it off found eight real
  gaps, none in `user` code alone: `engine/metta.pl`'s own
  `directory_file_path/3` directive ran before its existing
  `library(filesex)` import, two full imports (`distinct/2` for
  `'defined-name'/1`, `library(gensym)` for every compiled `'|->'`,
  `foldl-atom`, `map-atom` and `filter-atom` closure) were genuinely
  missing from the engine's own source, and five SWI-shipped libraries
  turned out to rely on autoload for their OWN internal cross-references:
  `library(ansi_term)`'s `~@` goal-printing calls a `portray_clause/1` it
  never imports, `library(ugraphs)`'s `top_sort/2` calls an `append/2` its
  own partial `:- autoload/2` line does not cover, `library(clpb)` does
  not declare `library(lists)`, `library(pairs)` or `library(apply)` at
  all, and `library(pcre)`'s option parsing needs `library(option)`
  alongside the four it does declare. Each is now either qualified at the
  call site (`prolog_listing:portray_clause/N`, the only fix that does not
  touch a shipped library's own namespace) or explicitly imported into
  that library's own module (`ugraphs:use_module(library(lists),
  [append/2])` and siblings for clpb and pcre), because this repository
  does not ship those libraries and cannot fix their own missing
  declarations any other way.

  One surveyed claim did not survive contact: a residual "one silently
  lost prelude clause" was real (`type-cast-holds`, 23 clauses against 22)
  but its blamed cause was a masking symptom, not the defect.
  `library(gensym)` alone, with nothing else preloaded, restores the
  clause completely and the `prolog_clause:inlined_unification/7: Unknown
  procedure: prolog_clause:nth1/3` message some prior loads showed never
  appears at all once the real cause is fixed: SWI's own
  initialization-error reporting was trying to build a source-location
  diagnostic for the ORIGINAL, un-preloaded `gensym/2` error, and that
  diagnostic call is what hit `library(prolog_clause)`'s own separate,
  unrelated undeclared dependency on `nth1/3`, replacing the visible
  message with a secondary failure while the real one stayed hidden.

  `run.sh NO_AUTOLOAD=1` boots with the flag already set (a `-g` goal on
  the command line cannot: it runs only after every `-s`/`-l` file has
  already finished loading, in either order, and `engine/metta.pl` needs the
  flag set before its own first directive), so `NO_AUTOLOAD=1 sh test.sh`
  runs the property over the full corpus [measured 2026-08-18: 200/200
  examples/, both configurations otherwise identical]. `check.sh` does not
  gate it yet, since editing that file is outside this change; the line
  `run GATE   no-autoload  sh -c "cd '$HERE' && NO_AUTOLOAD=1 sh
  test.sh"` reuses `test.sh`'s own runner and skip list unchanged.
  Explicit imports cost real instructions: +1.50% on a bare boot with no
  backend loaded, +0.54% with one loaded, +0.14% amortized over a full
  example run that also exercises the newly-fixed opt-in libraries
  [measured 2026-08-18: interleaved min-of-3, `perf stat -e
  instructions:u`, under 0.003% spread within each side].

- An empty Python tuple no longer kills a run through the library. janus
  renders a Python tuple as a `-` compound, so `(1, 2)` arrives as `1-2`
  and `()` arrives as SWI's zero-arity compound `-()`; the shim's encoder
  used `=../2`, which raises `Domain error: compound_non_zero_arity` on
  that term. It reached ordinary Python return values: `''.split()` of an
  empty string, `np.shape` of a scalar, a zero-row fetch. Only the library
  was affected, because the engine has its own writer and never ran that
  clause, which is why no lane saw it.

- The stated size of the example corpus is now derived from the runners'
  own definition instead of restated in three places. `examples/README.md`
  said 184, `llms.txt` said 242 (a glob counting 24 symlink aliases and 12
  fixtures), and the survey ledger said 169. Two hundred run: 242 paths,
  218 of them regular files, 206 discovered once fixtures are excluded,
  200 once the six declared skips are.

- `examples/libraries/test_datetime.metta` checks what is checkable about a
  clock instead of printing one. Three of its forms printed a live reading
  and asserted nothing, so the file could not be reproduced and verified
  none of what it demonstrated.

- An example's `check()` no longer asserts a wrong value, it raises.
  `python -O` strips `assert` statements outright while the `print` beside
  one still ran, so a wrong value printed as a passing check and exited 0:
  every example's self-verification silently vanished under that flag.
  `check()` raises `CheckFailed` now, an ordinary exception `-O` cannot
  touch, so a wrong value stops the example the same way with or without
  it, and `done()` also refuses to print `OK` for an example that checked
  nothing before calling it.

- `test.sh`'s `FAILURE in $f:` block now prints an example's whole output
  instead of the `!(test A B)` trace it used to filter for. That filter,
  `grep "is " | grep " should "`, only ever matches the one line a `test`
  mismatch prints; every other failure shape, an `assertEqual` mismatch, a
  syntax error, an undefined predicate, throws an uncaught exception the
  engine reports to STDERR, which the runner never captured in the first
  place, so the block printed blank. The exit code already failed the run
  either way, but a human reading a red one saw the file name and nothing
  about why. The filter still runs, now only for a PASSING file, where it
  is a legitimate summary rather than the unfiltered trace: five checks in
  one file print 273 lines on their own [measured 2026-08-18].

- **Breaking.** The Python name is the MeTTa name, verbatim. Nine places
  in the surface used to rewrite it, `fn.__name__.replace("_", "-")`, so
  `@m.register_op def p_digit(...)` registered `p-digit` and the name the
  author wrote never appeared in the space. Hyphens remain the MeTTa
  convention, and Python cannot spell one, so a hyphenated name is now
  ASKED for and visible at the registration:

      @m.register_op(name="p-digit")
      def p_digit(image, cls): ...

  `@m.define` gained the same `name=`, including alongside `prolog=`,
  because without it a compiled definition had no way to carry a
  hyphenated name at all. `integrate.module_ops` and `@m.type`'s method
  names stopped rewriting too.

  Two lookups went with it. A `@m.define` body used to retry a called
  identifier hyphenated, so `sqrt_math(x)` silently compiled to
  `(sqrt-math x)`; it now resolves the name as written, and a body
  reaches a hyphenated engine function through an alias equation it can
  spell, `(= (sqrt_math $x) (sqrt-math $x))`. The `why()` diagnostic no
  longer suggests a hyphenated twin, which `get_close_matches` already
  covers as an ordinary near miss.

  What prompted it was the inconsistency: the rewrite applied to
  function names but not to match-pattern heads, so
  `match(nn_next(b, x, y), ...)` in a define body compiled to
  `(nn_next ...)`, matched none of the `(nn-next ...)` atoms in the
  space, and answered nothing without an error. Removing the rewrite
  removes the class of mismatch rather than extending it to one more
  position.

- `ClosureView`'s own example did not work. It documented
  `deps.reachable("app")` and `("app", "libc") in deps`, and a Python
  `str` is a MeTTa String rather than the symbol of the same spelling, so
  both answered nothing rather than the closure. The nodes are atoms,
  `reachable(S.app)`, and the docstring says so now, which is also what
  the generated reference page carries.

- A registered operation could silently shadow a Prolog predicate the
  engine itself calls. A MeTTa name compiles to a Prolog predicate of one
  higher arity, and for several ordinary words that predicate already
  belongs to SWI: registering an operation called `format` put a
  `user:format/2` in front of the system's own, after which every
  `println!` the engine ran reached the operation, printed nothing and
  raised nothing (reproduced 2026-08-18: captured output went from
  `"(hi)\n"` to `""`). `succ`, `plus`, `print`, `between` and
  `nb_getval` were shadowable the same way. The name is now checked
  before the assert rather than by letting the assert fail, since for
  these names the assert was succeeding, and the test is
  defined-and-not-dynamic: a system builtin and a library import are
  both static, an autoloadable name reports defined before it has ever
  been loaded, and an operation of ours stays dynamic, so re-registering
  one is not mistaken for a collision.
- Where the name really is taken, the refusal is now MeTTa's rather than
  SWI's. `assertz/2: No permission to modify static procedure
  'dcg_basics:digit/3'` names a module the author never imported and an
  arity one higher than the one they wrote; the refusal now names the
  operation, its MeTTa arity, the Prolog predicate it would collide
  with, the module that owns it, and the two ways out. This is the
  operation route's twin of what `assert_function_clause/3` already did
  for the equation route.
- Unregistering an operation whose name a protected system predicate
  shares raised instead of unregistering: the walk asking whether any
  clause of the name survives called `clause/3` on every arity of it,
  and `clause/3` refuses a private procedure. A builtin is never a
  clause of ours, so it is skipped rather than inspected.

- Rewrote `llms.txt` and gated it. The file an agent reads instead of the
  tree had gone stale in the way that matters most: it named
  `m.fresh_space()` and `m.value()` after both were renamed, documented
  `petta.matching` and `petta.measure` after both were deleted, and
  omitted the whole `declare_*` family, `petta.spaces`,
  `petta.structures`, `petta.tables`, the manifest, the CLI and the
  concurrency surface. It now carries an index of every source of
  information in the repository beside the packed API, and
  `bindings/python/tools/llmsdoc.py` checks every name, path, count, special form,
  stream rewrite, builtin and library in it against the running engine
  and the real tree. Each of the five drift classes above was reproduced
  against the lane before it was wired in, so the check is known to fail
  and not merely known to pass.

- `using=` reaches the term doors, not just `run()`. `eval`, `one` and
  `first`, and their `AsyncMeTTa` twins, now take the same mapping of
  bare symbols to host values, so a Python object can be named inside a
  single expression without being written into a space first. The gap
  was found by writing a torch example: routing one classifier output
  through a MeTTa rule needed `m.one("(gated v)", using={"v": tensor})`
  and only `run` accepted it, which forced the caller to either wrap the
  term in a `!` directive or add and remove a fact around the call.
  `using=` and `residuals=` are refused together rather than silently
  ignoring one: residuals leave the door through a different predicate
  that has no substitution step, and pretending otherwise would answer
  an unsubstituted term.

- Added a verification mode for the specializer, and a gate lane that
  runs it over the whole example corpus. Under
  `PETTA_VERIFY_SPECIALIZATIONS` (or
  `(pragma! verify-specializations True)`) each specialization is run
  against the generic call the first time it fires and the complete
  answer lists are compared with variant equality, so a specialization
  that answers differently throws instead of being believed. It is off by
  default and emits a byte-identical goal when off, so production pays
  nothing, and the checked run is bounded whole and reports what it could
  not check rather than claiming completeness, translation validation's
  own shape. The lane costs about ten seconds across the corpus and found
  a real defect on its first outing, the recursive-specialization bug
  below.
- Added in-language resource control and layout, from the MeTTaLog
  comparison: `(inferences $n $expr)` is `timeout`'s deterministic twin,
  the same bound `run(inferences=)` applies one tier up, so a program
  can bound its own subexpression at a step count that is identical on
  every machine; `(with-pragma! (($key $value) ...) $expr)` scopes
  interpreter settings to one expression, restoring the previous values
  in reverse on every exit path; and `(pretty-atom $x)`, with
  `petta.atoms.pretty(atom, width=78)` as its Python twin, lays a deep
  term out over lines instead of one 135-character line, the two
  differentially pinned against each other. Bound expiry now throws the
  reserved limit envelopes, so a pragma bound classifies as
  `TimeLimitError`/`InferenceLimitError` exactly as a per-call kwarg
  does, and is a control signal no `catch` can eat.
- Added backward integer arithmetic: `+`, `-`, `*` and `/` solve for one
  unbound argument among integers, so `(let 4 (- $x 1) $x)` answers 5
  and `(let 6 (* $x 2) $x)` answers 3, MeTTaLog's relational compilation
  taken at the predicate so every call site inherits it. Exactness is
  honest, `(let 7 (* $x 2) $x)` answers nothing rather than rounding;
  ground and float paths are untouched, and two unbound arguments stay
  an instantiation error, because bounded solving is arithmetic's job
  and constraint propagation is `lib_constraints`'.
- Added source positions without touching the engine's hot path:
  between top-level forms the grammar allows only whitespace and
  comments, and the reader's form texts are verbatim slices, so a
  deterministic walk recovers every form's exact line and column and
  refuses loudly if the reader and locator ever disagree, the
  subterm_positions philosophy with consumers paying and the compile
  path paying nothing. `petta.lint.lint_file(path)` anchors each
  finding to its source form through alpha-matching and carries
  file/line/column in the payload; `python -m petta lint` prints
  `path:line:` findings; and the MeTTa library reference cites each
  `@doc` entry's source line.
- Added the LSP diagnostic vocabulary to lint findings: `severity`
  (error/warning/information/hint, assigned across every existing
  check), `suggestion` (possibly-undefined references now carry a
  did-you-mean from the engine's own 208 known names plus the space's
  vocabulary), `docs_link`, a structured `payload`, and `autofix`, an
  ATOM carrying the stored equation with the simplification applied, so
  applying a fix is remove-then-add with no source positions needed.
  And added the nine checks the LSP comparison showed buildable: the
  seven syntactic simplification rules (`constant-if-true`,
  `constant-if-false`, `if-same-branches`, `if-true-false`,
  `superposed-empty`, `superposed-single`, `duplicate-binder`, each
  with its rewrite where one exists), `inconsistent-arity`
  (information, silenced by an arrow, because multi-arity dispatch is
  legal and the arrow states intent), and `type-mismatch` (error: a
  ground argument whose engine `get-type` contradicts the declared
  arrow slot, conservative around metatypes and parametric slots).
- Added the observability guide page: nine doors (`why()`, derivation
  trees, `.explain()`, trace, stats, profile, table-stats, lint, and
  standing queries) mapped to the nine questions they answer, with
  sibling pointers in the key docstrings. Beside it, a match/case
  section in the atoms guide showing `case Expr([Sym("edge"), a, b])`
  as the Python twin of `(edge $a $b)` and where case deliberately is
  not unification; per-attribute slot docstrings on the atom classes,
  so `help(Expr)` documents `children` in place; compliance suites that
  refuse a collectible `Test*` subclass with no `provider` or
  `gateway_url` fixture at class-definition time, where the traceback
  points at the class; the `petta` logger namespace and `tqdm`
  composition each documented in one line; and the deprecation policy
  stated: a surface removal warns with `DeprecationWarning` for one
  release before it goes.
- Added the thread-safety and serialization guarantees page: per type
  and per operation, what is atomic, what locks, and what a caller must
  serialize, Python's own documentation convention pointed at PeTTa.
  Every claim is pinned by a named test, two of them new: bare threads
  sharing the home engine answer correctly under contention, and a
  `with m.limits(...)` block on the event loop bounds engine work on
  the async worker thread, because scoped state rides contextvars and
  each request runs inside the submitting task's context. The page also
  records why the current-space scope needs no Python-side migration:
  it is an engine global, per engine and therefore per thread, and the
  package's one `threading.local` is deliberately thread-keyed because
  Prolog engines attach per OS thread.
- Added the provider ecosystem's entry-point groups beside
  `petta.integrations`: a package advertises a provider factory under
  `petta.spaces` or the directory of sources it ships under
  `petta.libraries`, and the app loads by NAME through
  `integrate.entry_points(group)` (unloaded discovery) and
  `integrate.load_entry_point(name, *args, group=...)` (a callable
  target is a factory, called with your arguments; a non-callable one
  answers as-is). Nothing auto-registers on import, and an unknown name
  refuses by listing what is installed.
- Added the subscription lifecycle pair: a `Subscription` is a context
  manager, cancelling on exit, and `events(timeout=None)` streams the
  no-callback queue to a consumer thread that sleeps on a condition
  variable between arrivals instead of polling `drain()`. The stream
  ends at cancellation, queued leftovers delivered first, or after
  `timeout` quiet seconds; a callback subscription refuses it, and bare
  `iter(sub)` stays deliberately absent because iteration that blocks
  should say so by name.
- Added `petta.spaces.diff(a, b)`, what `digest()` cannot say: HOW two
  spaces differ, as the multiset difference over enumeration with
  alpha-equivalent atoms counting as the same atom, digest's own
  equivalence; each side is a `MeTTa` handle or a provider and is
  enumerated exactly once. And added `m.copy()` with the `copy.copy`
  protocol: this space's contents in a new anonymous space through the
  bulk door, so equations copy as equations and keep running; there is
  deliberately no `__deepcopy__`, since stored Python objects keep
  their identity across the clone.
- Added the MeTTa half of the documentation pipeline:
  `bindings/python/tools/libdoc.py` generates
  `website/reference/metta-libraries.md` from each `lib_*.metta`
  library's own `(@doc ...)` atoms, read through the engine's reader and
  never run, so a library whose backend is absent still documents. The
  page's coverage table is the burn-down surface, interrogate's role for
  the MeTTa side, and the gate holds the page current the way the
  Python reference gate does.
- Added `python -m petta` subcommands on the library engine, the stdlib
  "Command-line usage" chapter for the installed wheel: `run` prints
  each `!` answer group, `repl` is an interactive loop that reads
  multi-line forms (strings and comments included) and reports errors
  without dying, `serve` exposes spaces over HTTP with host/port/
  allowlist/token flags, `boot` assembles a `(boot ...)` manifest and
  blocks while its servers run, `lint` exits nonzero on findings, and
  `doc` prints a name's `(@doc ...)` documentation. The bare `petta`
  console script keeps upstream's swipl-launcher contract exactly.
- Added `examples/integration/networkx_space.py`: the metagraph reading
  made executable on the public surface alone. Any space's links view as
  a networkx graph, an nx algorithm answers what no match can express,
  and the answer writes back as atoms; the same call runs unchanged
  against the SQL bridge because it rides the one seam. An n-ary link
  has no default graph reading, so the projection is the caller's to
  name, pairwise or bipartite, and anything else is refused.
- Added `Rows.pipe(fn, *args, **kwargs)`, pandas' chaining shape, so a
  post-processing pipeline reads left to right; `__rich__` on Rows, so a
  rich console draws query answers as a real table with the same
  display_rows bound and why() hint the notebook table carries; and
  `__rich_repr__` on expressions, so rich.pretty prints a deep term as
  an indented tree of its children. rich stays the caller's dependency:
  only rich itself calls the protocol methods.
- Added engine injection into registered operations: a parameter
  annotated `petta.MeTTa` is the framework's to fill, FastAPI's Depends
  read with the house convention that the annotation is the request. The
  engine injects itself bound to the calling context's space, so an
  operation invoked from a program running in &kb queries &kb; the slot
  never counts toward MeTTa arities or the declared arrow, and only
  operations that ask pay the weaving.
- Added `.explain()` on prepared queries and cursors, and on their async
  twins: the query's plan reflected rather than run, polars'
  `LazyFrame.explain` and SQL's `EXPLAIN` pointed at the space seam.
  Per pattern it shows the pushdown class and which rule decided it, a
  declared `(handles ...)` entry, the provider's own `pushdown` method,
  or silence, in exactly the precedence the match uses; a conjunction
  line names what a planning provider claimed whole and what the engine
  joins; refused shapes report the refusing entry; stored spaces answer
  the one true line. The engine door, `petta_py_explain`, preflights the
  same refuse guard the match consults and answers claimed/rest as
  indexes so the caller's variable names survive rendering.
- Added `petta.boot(manifest)`: deployment as knowledge. A manifest is a
  MeTTa file of `(boot ...)` forms over a closed vocabulary, each sugar
  for exactly one existing call: `(load "rules.metta")` for `m.load`
  resolved against the manifest's directory, `(attach &crm "url")` for
  `petta.remote.attach`, `(bridge &db <shape> <row>)` for a declared and
  registered `TableBridge` (live connections cross through the
  `connections=` mapping, checked both directions), and
  `(serve (&self &crm) 8700)` for `petta.remote.serve`. The whole
  manifest validates before anything performs, with every problem
  listed; forms perform in source order and each lands as its own
  `(boot ...)` atom, so the running app can query its own topology. The
  answered `Boot` handle owns the started servers and closes them, on
  the mid-way failure path too, while performed writes stand, the same
  law the engine's own guards follow. The engine door underneath,
  `petta_py_read_forms`, reads a source's forms without compiling,
  storing, or running any.
- Added a reference page for `petta.tables`, which had none, and listed
  `petta.tables`, `petta.spaces`, and `petta.structures` in the module
  index tables they were missing from. `petta.tables` now also resolves
  lazily as a package attribute like its peer modules.
- Added `@petta.record`, one decorator that makes a dataclass, NamedTuple,
  or Enum a full citizen of the type story: two-way conversion registers
  at decoration (an unregistrable class fails right there), and the
  class's `(: ...)` declarations land in the default space the moment an
  engine exists, on the first `MeTTa()` construction otherwise, so the
  decorator runs at module import time without booting anything. The
  declared class then works as a `cast` and `query(into=)` target.
  `petta.ops.class_declarations(cls)` exposes the emitted atoms, and
  every underlying registration call stays public for custom shapes.
- Added the engine prelude: the Hyperon-Experimental vocabulary that lived
  in `lib_he` is part of the core engine now, compiled from
  `engine/prelude.metta` at startup by the same translator that compiles a
  program's own equations. Every form is reachable with no `import!`,
  shadowable per named space exactly as builtins are, and stored as an
  atom in no space, so a program enumerating `&self` sees only its own
  writes. The promoted forms: the `assert` family (`assertEqual`,
  `assertAlphaEqual`, the `ToResult` and `Msg` variants,
  `assertIncludes`), `if-equal`, `if-equal2`, `if-error`,
  `return-on-error`, `for-each-in-atom`, `unquote`, `noreduce-eq`,
  `is-function`, `match-types`, `match-type-or`, and `type-cast`.
  `get-type-space` is a native builtin taking ANY space, where the
  library stub matched the literal `&self` only. Prelude declarations
  live in their own engine register, read after a program's own, so a
  user redeclaration wins; an `Atom` parameter declared there masks call
  sites the way the `my-if` tutorial mechanism describes.
- Added the documentation vocabulary as engine builtins, promoted from
  `lib_doc` with the design it already had, documentation is atoms in a
  space and retrieval is a match: `get-doc`, `help!`, `documented`,
  `defined-name`, `undocumented`, each with a `-space` twin selecting
  any space, resolving against the CURRENT context rather than the
  literal `&self` the library matched. `get-doc` and `help!` fall back
  to the engine's own doc register, where the prelude documents every
  form it ships, so `(help! type-cast)` answers with no import; the
  enumerators stay program-scoped on purpose, so "what have I
  documented" and "what did I forget" are answers about YOUR program,
  never padded with engine vocabulary. `@doc` forms remain inert data
  constructors, and a user program's own doc atoms answer as written.
- A user definition WINS over the prelude, entirely: compiling an
  equation for a prelude-owned name in `&self` evicts the prelude's
  clauses and declarations for that name first, at every compile door,
  so a program defining its own `match-types` means ITS `match-types`,
  exactly as it did before the name was promoted. Eviction is one-way,
  the same as redefining any function; named spaces need none of this
  because their clauses already shadow through their own module.
- Several promotions fix the library's contracts against the mechanised
  arbiter (LeaTTa, measured against pinned Hyperon 0.2.10), the way
  `add-reduct`'s promotion fixed its: `if-equal` compares by
  alpha-equivalence, not `==`; `assertEqual` and `assertAlphaEqual` take
  `Atom` parameters and compare result sets, as their `Msg` twins always
  did; `match-types` is unification with `%Undefined%`/`Atom` wildcards, not
  equality; `match-type-or` takes upstream's `(folded next type)`
  parameter order; and `type-cast` is undeclared on purpose, so an
  ill-typed subject reports its own error instead of being swallowed by
  an `Atom` mask.
- Completed the container and operator protocols on `MeTTa`: an empty
  space is `True` (a space is a handle, not a value that dwindles);
  `m[pattern]` answers `query(pattern)` and `m[p1, p2]` spells the join,
  with slices refused toward `query(limit=)` and `stream()`;
  `del m[pattern]` removes every unifying occurrence and raises
  `KeyError` when nothing unified, `remove()` staying the door that
  reports absence as `False`; and `m |= other` is the bulk merge, taking
  another space (equations included, compiled on arrival), a registered
  space name, or an iterable of atoms, while `+=` keeps `add()`'s
  one-atom lifted reading so the two spellings never read one operand
  two ways. A dict is refused by `|=` because `add()` lifts the same
  dict into one grounded atom.
- Added `m.space_names()` and the engine predicate `metta_space_names/1`
  behind it: every space name the engine registers, sorted, `&self` and
  `&petta` from boot, every written native space, every bound foreign
  space. Naming a space never registers it; writing or binding does.
- Added structured fields on the whole `PettaError` family, the way
  `OSError.errno` rides beside its message: `.atom` (the MeTTa atom the
  error is about), `.space`, `.operation` and `.capability`, each None
  when the error has no such part, the message unchanged either way. A
  provider capability refusal now carries all three of its parts as
  data instead of only as a sentence.
- Added `MettaResultError` and the one-sentence error policy behind it:
  an `(Error culprit reason)` answer stays DATA at every multiset door
  (`eval`, `run`, `fn.all`, streams) and RAISES at every single-value
  door (`one`, `first`, calling a function), carrying `.atom`,
  `.culprit` and `.reason`. `first()`'s tolerance covers absence, not
  errors, because None must keep meaning "no answers".
- Added `Rows.raise_for_errors()`: query rows are bindings, so stored
  `(Error ...)` records stay data through every Rows door; this is the
  explicit bridge, answering self when clean so it chains, raising one
  error plainly and several as one `ExceptionGroup`.
- A `PettaError` raised inside a Python callback (a provider refusing a
  write, a seam contract violation) now crosses the engine and
  re-arrives as the very same exception object, structured fields
  intact, instead of an `EngineError` holding a transcript of it. An op
  author's own exception classes still arrive wrapped in `EngineError`,
  the boundary they crossed staying visible.
- `m.fn()` speaks the whole function protocol now, answering from
  MeTTa's own declarations: `__name__` and space-qualified
  `__qualname__`; `__doc__` formatted from the space's `(@doc ...)`
  atom, with builtins answering from the engine's register, so
  `help(m.fn("inc"))` shows documentation written in MeTTa;
  `__signature__` built from the declared arrow, so
  `inspect.signature()` shows arity and parameter types, `(*args)` when
  no arrow is declared; `.type` as the declared type atom or None; and
  `.equations` as the stored `(= ...)` atoms, live from the space.
  `functools.partial` composes because the object is an ordinary
  callable; `__defaults__` and `__annotations__` are deliberately
  absent, because MeTTa has neither.
- Added `m.disassemble(name)` and `fn.compiled`: the Prolog clauses a
  name compiled to, one listing per registered arity in the space's own
  module. The `(= ...)` atoms are the source; this is what the engine
  runs, the translator's own `dis`.
- Watching a function change needs no new machinery and is now tested
  and documented as the watcher recipe: equations are atoms, so
  `subscribe("(= (f $x) $body)", callback, on="both")` fires on every
  equation added or removed, bindings included.
- Added `petta.spaces`, combinators composing existing spaces into new
  ones with zero engine changes, each an ordinary provider on the public
  seam: `union(*spaces)` reads every member as one space and refuses
  writes by capability (rdflib's aggregate reading; a union of multisets
  answers duplicates twice); `readonly(inner)` strips every write;
  `mapped(inner, declaration)` derives a shape view from one
  `(bridge <outer> <inner>)` pair, the tables bridge with unification
  where tables emits WHERE, both directions from the shared variables;
  `overlay(front, back)` reads both layers and writes, removes, and
  clears the front only, ChainMap's rule stated loudly. Combinators
  take combinators, and overlay and mapped pass the conformance kit.
- Added the ladder's sugar tier, every rung documented as sugar for the
  rung below and the long spelling never leaving. Module-level
  `petta.run/query/add/remove/eval/fn/space` over one lazily created
  default engine, `petta.default_engine()` the named escape hatch
  (random's and logging's shape). `with m.limits(timeout=,
  inferences=)` sets scoped default bounds, contextvars underneath so
  the scope is async-correct, per-call kwargs still overriding.
  `m.query(..., into=Edge)` shapes each row into a dataclass,
  NamedTuple, or TypedDict matched by field name, sqlite3's row_factory
  reading, with primitive annotations CHECKED at the door and typed
  fields built through the two-way translator. `with m.batch():`
  collects a region's adds and crosses once at exit, with the sharp
  edges stated and enforced: reads inside see the pre-batch space,
  remove and clear refuse inside their space's block, an exception
  discards, and a batch inside transaction() composes economy with
  atomicity. A shipped pytest plugin (pytest11 entry point) provides
  `metta` and `scratch_space` fixtures a project's conftest can
  override, and `petta.testing` exports `ground_atoms()` and
  `patterns()` beside the existing strategies, so anyone can fuzz
  their own provider the way the kit does.
- Fixed a divergence the new ClosureView surfaced: the specializer
  cloned a TABLED function when a call's argument happened to name a
  defined function (a graph node called `d`, with `(= (d $x) ...)`
  defined anywhere in the process), and the clone lost its tabling, so
  the recursion SLG resolution terminated ran to a 27,525-frame loop.
  maybe_specialize_call now refuses to specialize a tabled function,
  read from lib_tabling's own `(tabled ...)` reflection facts, one
  indexed probe at translate time.
- Added `petta.structures`, data structures with MeTTa's semantics,
  each implemented where it is fastest. The pure tier runs on the atom
  kernel and imports without janus in the process: `PatternMap` (a
  MutableMapping whose ground keys hash like dict keys and whose
  `matching()` answers the dispatch question through head/arity
  buckets), `MatchIndex` (many patterns, one atom, answered sublinearly
  through an imperfect discrimination tree with unify confirming, so
  nonlinear patterns are exact; property-tested against the brute-force
  oracle), and `AlphaSet` (membership modulo variable renaming, through
  canonical renaming, property-tested against pairwise alpha_eq). The
  engine-backed tier crosses deliberately: `TabledMap` (a view of a
  tabled function; a write to a space it reads by literal name
  invalidates exactly the affected tables, the safety functools.cache
  lacks), `LiveView` (one pattern materialised and maintained by
  subscription events, seeded and subscribed inside one transaction so
  no write falls between, mirroring multiset removal exactly), and
  `ClosureView` (reachability over a stored relation, tabled from birth
  so cyclic and symmetric closures terminate and stay fresh).
- `lib_datastructures` grows a Hinze-Paterson 2-3 finger tree: push and
  pop at both ends in amortized O(1), concatenation in O(log n), so one
  term-shaped structure serves as sequence, deque, and staging buffer
  for programs written in MeTTa itself, every form @doc-documented,
  exercised under the gate by
  examples/libraries/datastructures_fingertree.metta.
- Added `petta.atoms.substitute(atom, bindings)`, unify's companion:
  the atom with every bound variable replaced, so
  `substitute(pattern, unify(pattern, atom))` is the matched instance.
  The remote server's bounded match and the mapped combinator both
  ride it.
- AsyncMeTTa reaches full parity with the synchronous surface, and the
  parity is computed rather than curated: the suite asserts every public
  MeTTa method exists on AsyncMeTTa minus a three-entry ledger with
  stated reasons (`pool`, asyncio's fan-out being workers plus gather;
  `prolog`, an interactive toplevel; `transactional`, a transaction body
  being a closed synchronous goal). The mechanical members are one
  worker round trip each; the structural ones take their async shapes:
  `stats()` and `assuming()` as async context managers, `prepare()`
  with awaitable solve, `stream()` as an async cursor pulling one row
  per round trip, `subscribe()` as an async event stream fed through
  call_soon_threadsafe (a class, not an async generator, so aclose() is
  explicit), `fn()` as an async callable with the one/first/all triple,
  and `transaction(fn)` running fn on the worker inside one engine
  transaction, fn receiving the worker's own synchronous handle.
- The remote space protocol is revision 2, and what crosses the wire is
  now stated instead of implied: the caller's answer limit crosses as an
  optional `bound` field on `/match` that a server may honor exactly
  (only sound for an exact matcher; ignoring it over-answers and stays
  sound), `GET /health` carries `capabilities` and whether bound is
  honored, `RemoteSpace.server_capabilities()` reads the advertisement
  client-side, and the protocol page gained a projection table naming
  every seam capability, whether it crosses, and why. Both TypeScript
  reference servers updated: the store server honors bound, the
  MeTTaScript server deliberately does not (its match over-approximates,
  and truncating an over-approximation can drop true answers).
- Fixed three holes in `serve()` the compliance suite never saw because
  it was only ever pointed at the reference servers: `add_many` was
  documented and sent by the client but unhandled, so bulk adds against
  our own server failed; `GET /health` was documented but unimplemented;
  and non-POST methods answered 501 where the contract says 405. The
  suite now certifies our own `serve()` too, and removal by a bare
  variable (`$everything`, the protocol's own cleanup idiom) removes
  every stored atom, equations and their compiled clauses included.
- The match law is now stated as the engine actually matches:
  occurs-checked unification, the arbiter's own variable cases, so a
  rational-tree pair is never an answer a server owes, and answering one
  anyway is legal surplus the client discards. The conformance kit's
  unifier gained the occurs check, and its match contract accepts a
  candidate either as the stored atom or as the pattern's unification
  result with it, both of which preserve the pattern's answer set, so a
  gateway that answers instantiations (as `serve()` does) certifies.
- Fixed a crash and a divergence around rational-tree candidates: a
  repeated-variable query like `(rt $y $y)` over a stored
  `(rt (f $x) $x)` once died in the row encoder at a 53-million-frame
  walk (the cyclic join passed match_native's template guard because the
  bindings live outside the template), and the same match answered
  differently depending on whether the out template mentioned the cyclic
  variable. The occurs check now runs once per candidate in
  native_expression and once per row in the query lanes: the cyclic
  candidate fails that answer and enumeration continues. The measured
  cost is one inference per answer row on the query lanes, rebaselined
  with the attribution in the benchmark ledger.
- Added `m.transaction(callable)` and the `m.transactional` decorator:
  the Python door of the MeTTa `(transaction ...)` form, riding the
  same `petta_transaction/1`, so foreign-space enlistment and nesting
  behave identically in both languages. The callable runs now and its
  return value comes back identity-preserved; a raise is the one
  rollback trigger, re-raised as itself with the boundary in its chain,
  stored atoms and compiled equations rolled back together; an inner
  commit stays relative to its outer transaction. There is deliberately
  no `with` form, because SWI's transaction/1 takes a closed goal and
  an open begin/commit would lie about the isolation provided.

- Added the stdlib `unify` special form: `(unify a b then else)` runs the
  then branch once per binding set under which the operands match and the
  else branch exactly when none exists, operands unevaluated, only the
  selected branch evaluated, numbers compared promoted so `1` matches
  `1.0`. A space operand routes through the engine's own match, so
  `(unify &self (friend $who Alice) $who no-friends)` answers each friend.
- Added custom matching for grounded values, Hyperon's CustomMatch: any
  Python object whose class defines `match_` owns its matching logic
  inside `unify` with no registration, yielding bindings, values or
  residues for the operand it met (`petta.foreign.CustomMatch`), and
  Prolog-hosted values participate through the `metta_matchable_value/1`
  and `metta_custom_match/2` seams.
- Added `&self` as the reserved token for the space the code lives in:
  the reader substitutes it for the hosting space's name exactly where
  `bind!` tokens substitute, so `(match &self ...)`, `(add-atom &self
  ...)` and `(unify &self ...)` mean "this space" wherever source is
  read, text handed to `eval()` included; under the CLI the program
  space is already named `&self` and nothing changes. A term built at
  run time keeps the literal atom, the same boundary stored data has.
- Added `Empty` as the branch remover: a finished result that is the
  symbol `Empty` is not returned among other results, pruned at every
  collapse and runnable aggregation, per minimal MeTTa.

- Added the typed `petta` Python package for atoms, spaces, evaluation,
  operations, queries, persistence, diagnostics, and engine controls.
- Added async, remote, array, dataframe, DAS, foreign-space, and
  Python-object integration surfaces.
- Added a generated Python API reference, task guides, executable examples,
  and an end-to-end notebook tour.
- Added deterministic inference and retired-instruction regression gates,
  property tests, differential tests, package-install tests, and static checks.
- Added named MORK spaces and bulk Python space writes.
- Added `Rows.to_dicts()` for Python-native row mappings.
- Added `Rows.why()` to explain an empty eager query as a pattern miss,
  failed join, or rejecting guard.
- Added exact unregister counterparts for Python type, object formatter,
  protocol type, protocol formatter, and reflector registrations.
- Added machine-readable citation metadata and this release changelog.
- Added the `rules` space capability: a foreign space can hold EQUATIONS, not
  only facts. The engine compiles an equation added to such a space exactly as
  it compiles a native one, so a rule in a foreign space is the same compiled
  clause a native one is, and every evaluation rule (chaining, an unevaluated
  `Atom` parameter, `if` laziness, recursion, nondeterminism, non-totality)
  behaves identically. An equation added to a space that does not declare
  `rules` is refused at `add-atom` rather than stored inert. MORK declares it.
- Added `metta_foreign_plan/5` and the Python `Planner` protocol, the claim
  seam: a provider is offered a whole conjunction before the engine splits it,
  and may claim all or part of it. Declining is the default and needs no
  clause. MORK claims its own worst-case-optimal join through it, measured at
  68x fewer retired instructions than the engine's split on a query whose
  intermediates dominate its output.
- Added `metta_foreign_add_many/2` and the Python `BulkAdder` protocol, so a
  provider can take a whole batch in one crossing. MORK's bulk loader is now
  one implementer of it rather than a special case inside the Python bridge.
- Added `petta.testing.SpaceComplianceSuite`, the engine's own space tests as a
  class a provider author subclasses. Every test reads the provider's `can_run`
  and skips what it does not declare, and the run reports which capabilities
  were exercised; a provider that declares nothing fails rather than passing by
  skipping everything. It is the rung above `check_space_provider`, which asks
  whether a provider keeps its own promises, where this asks whether the engine's
  expectations hold of it.
- Added a per-pattern pushdown classification to the space seam. A provider
  answers `"exact"` for a pattern when every candidate it yields for that
  pattern matches, and only then is it given the caller's bound to truncate to;
  `check_space_provider` tests the claim against the provider's own output.
  Prolog providers declare it with `metta_foreign_pushdown/3`, Python providers
  with a `pushdown(pattern)` method.
- Added `(table-stats (f $x))`, reporting a tabled function's tables, answers,
  completed calls, invalidations and re-evaluations. A write the table's own
  subgoal does not read leaves it valid rather than merely leaving its answers
  unchanged, which these counters are what make visible.
- Added `control_exception/1` as an extension seam, so a library that raises its
  own cancellation or budget signal declares it and every recovery site in the
  engine lets it through instead of swallowing it.
- Added `petta.Handle`, the identity carrier for native engine values: a C
  blob reaching Python arrives as an opaque atom that resolves back to the
  very same object, so mutation and accessor calls survive the round trip
  and a Python function can unpack the structure through its extension's
  own accessors. It used to arrive silently as its printed string, which
  made the round trip impossible. `release()` frees the engine-side
  registry entry; a released handle raises by id.
- Added `petta.tables.TableBridge`, a complete table-backed space provider
  derived from one MeTTa bridge declaration,
  `(bridge (edge $a $b) (row edges (a $a) (b $b)))`: WHERE from bound
  positions, the equalities repeated variables demand, INSERT from
  grounding, and pushdown claims the conformance kit verifies. The
  declaration is the converter, both directions, the way a MeTTa pattern
  pair is.
- Added `add_many` to the remote space protocol and `RemoteSpace`: a batch
  crosses in one request, the engine's own bulk-door law on the wire, so
  `m.space(name).add(a, b, c)` against an attached gateway is one
  crossing; `GET /health` now names the protocol revision.
- Added `petta.testing.GatewayComplianceSuite`, the remote protocol's own
  conformance suite: subclass it with a `gateway_url` fixture and any
  implementation, in any language, is certified against the documented
  operations, refusal ladder, wide-integer refusal, and the kit's match
  contract and round-trip law. It caught the MeTTaScript reference
  backend's unifier refusing rational-tree matches, which its server now
  covers with a soundness envelope.
- Added schemas to `petta.tables`: a provider takes any number of bridge
  declarations, shapes answering together the way overlapping equations
  do, with a ground atom two shapes admit refused by name; declarations
  can live ctx-scoped in `&petta` (`tables.declare`, or MeTTa source
  adding the same atoms), and `TableBridge.from_context` builds the
  provider from what the context declares.
- Added the round-trip law to `check_space_provider`: with atoms stored
  through the provider's own add, every one must come back from
  enumeration intact up to variable renaming, because stored data keeps
  its literal atoms; a store that normalizes fails naming the atom.
- Added seam benchmarks to the gated inventory: `foreign-match` prices
  provider dispatch against an in-process provider, `table-bridge-match`
  the derived SQL bridge, and `handle-round-trip` a native handle out and
  back, each with a committed inference baseline.
- Added worked space-provider examples per language, each proven by the
  conformance kit: a mutex-guarded C store behind the Prolog seam
  (`examples/integration/c_space/`), SQLite through the derived bridge and
  CeTTa, a sibling MeTTa runtime, as both a storage backend and a
  bindings-level custom matcher (`bindings/python/examples/integration/`), and two
  production TypeScript servers speaking the remote-space protocol, one
  self-contained and one whose atoms live in a MeTTaScript space
  (`bindings/python/examples/integration/typescript_space/`, with the protocol
  itself documented in the website's live section).

- A recursive definition could silently answer NOTHING. An equation whose
  body calls itself with a ground higher-order argument compiles a clone
  for that call and a generic clause naming it, and the invalidation that
  runs when a function changes was abolishing exactly those clones after
  the clause naming them had been asserted, so the generic clause called
  an empty predicate: the direct call still answered through its own
  specialization, while a call arriving through a variable,
  `(let $g (+ 1) (f $g))`, answered nothing at all. Stale specializations
  are dropped BEFORE the new body compiles now, which is what
  invalidation always meant, and the dependent-recompile hooks still run
  after. Found by the new specialization differential on its first run
  over the example corpus.
- Six special forms were unusable in every named space: `timeout`,
  `elapsed`, `take`, `top`, `transaction` and the new bound forms hand
  their goal to a helper predicate, and the goal lost its module on the
  way in, so a space's own functions answered "Unknown procedure" for a
  definition plainly present. The helpers are `meta_predicate` now, the
  manual's own remedy, which costs +2 inferences per evaluation on the
  one benchmark lane that runs a wrapper form in a named space.
- A planning space provider could silently LOSE answers. The Python
  seam decoded the provider's claimed patterns into fresh copies, which
  split every join variable, and their identity was restored only as a
  side effect of the partition check's `msort` unification pairing the
  two lists in the same order. That coincidence held while plain
  variable addresses sorted alike on both sides and broke as soon as
  they did not, pairing the lists crosswise and over-constraining the
  claim. Claims resolve back to the caller's own terms by wire identity
  now, and the partition check is a check rather than a mechanism.

- One equation-compile door. Three doors used to carry the compile spine
  separately (spaces.pl's add_function_atom and filereader.pl's two
  process_form clauses), so a cross-cutting rule had to be hooked one
  door at a time, and one rule HAD drifted: the loader doors notified
  metta_on_function_changed but never invalidate_specializations, so an
  equation added by `m.run` or a compile-mode load left a prior
  specialization of the same name answering stale clauses.
  compile_metta_equation/4 now carries eviction, registration,
  translation, provenance, and the COMPLETE notification for all three,
  pinned by a plunit test, and the invalidation walk is guarded so a
  function with no specializations, which is nearly all of them, pays
  nothing: source-load's counter lane passes its unchanged floor.
- Pool `map`/`starmap` now report EVERY failure: one raises plainly and
  several raise together as one `ExceptionGroup` in input order, the
  library's raise_for_errors policy, where only the first in input order
  was raised before and the rest were silently dropped after draining. A
  worker's `KeyboardInterrupt` still reaches the caller, grouped when it
  arrived beside other failures.
- `petta.testing.check_space_provider`'s `atoms_to_store` now stores the
  atoms through the provider's own add, as its name always said, and
  refuses a provider that cannot add rather than comparing against
  contents that were never stored.
- The network JSON codec is now the engine's own reader and writer,
  SWI-Prolog's `library(json)`, behind the same two-function surface.
  Wide integers are exact in both directions because the engine's
  integers are unbounded, non-finite numbers are still refused both
  ways, an object that repeats a key is now refused instead of read
  last-wins, text that continues past one JSON value is refused, and
  object keys serialize in the engine's canonical order. The optional
  `orjson` accelerator is gone with the Python-side implementation.
- Put an executable Python installation and query example before native backend
  build instructions in the README.
- Set Python 3.11 as the package floor and consolidated build metadata in
  `pyproject.toml`.
- Split Python engine, atom, query, execution, persistence, compiler, and
  diagnostic responsibilities into focused modules.
- Made optional Python integration modules load on first access.
- Preserved concrete target classes through the static return types of `cast`
  and `build`, and made cast targets positional-only.
- Pointed package metadata at the canonical `trueagi-io/PeTTa` repository.
- Refused a source whose type declaration cannot type the function that source
  defines. `(: inc Number)` beside `(= (inc $x) ...)` types the symbol and not
  a call, so the call compiled with no check at all; it is now an error naming
  the arrow to write. One arrow among several declarations is enough, and
  `%Undefined%` opts out. Declarations arriving through `add_atom` are reported
  by `lint()` as `declaration-types-the-symbol` instead, because a build that
  writes its declarations one at a time is momentarily in that state.
- In-place type annotations are spelled `(: $x T)`, plain colon, told apart
  from stored `(: name type)` declarations by POSITION rather than by a second
  spelling. A pattern that is itself a colon expression stays structural, so a
  knowledge base query still retrieves what somebody wrote; below that, only
  `(: $variable expected)` annotates, and nothing looks inside a colon whose
  value slot is not a variable. This follows LeaTTa's mechanised Hyperon
  semantics. Issue #177 proposes `::` "when position cannot distinguish the two
  uses"; it can, and `::` is what MeTTa's own tutorials use for cons lists.

- Fixed three divergences in the space write path, which dispatched on where an
  atom is STORED before what it MEANS. A `(: f T)` added to a foreign space
  never recompiled `f`'s call sites; a type declaration added inside a batch
  skipped the recompile the same atom performs alone; and the Python bridge
  routed MORK's batch around `metta_add_atoms/2` entirely, so an equation added
  alongside any other atom was stored inert. A batch is now a transport
  optimisation and never a semantic one: only atoms whose add is a store and
  nothing more take a bulk crossing. The removal path had the same shape and
  the same fix, so an atom that compiles when added un-compiles when removed.

- Reported the names a source registered when it declares its exports and no
  extension, which is the shape of a single-file library. Every name registered
  and was callable, and the call still raised "register_prolog needs the names
  to register".
- Refused a second Prolog source claiming a name another source owns BEFORE it
  loads. The refusal used to come after the consult, by which time SWI had
  already replaced the incumbent's predicate and only warned, so the wrong
  author heard about it and the innocent library silently answered the
  newcomer's implementation. A source that declares its own exports has its
  declarations read out of the file without running the file.
- Answered a bounded query against a Prolog-only foreign space. There were two
  match hooks and the engine chose between them by asking whether ANY provider
  had declared the bounded form, which the Python shim always has: with Python
  in the process, a Prolog provider had the other form called and the query
  answered nothing.
- Preserved the active space during evaluation, tracing, definitions, and
  integration calls.
- Made save, registration, subscription, import, and remote lifecycle changes
  transactional or atomic at their public boundaries.
- Corrected reader, compiler, type dispatch, equality, and occurs-check defects
  covered by the regression suites.
- Reported the reader's syntax diagnostic without Janus's unknown-error wrapper.
- Made a dropped space release its integration installation records so a new
  space reusing the same name runs each installer again.

- Removed `petta.measure` and `petta.matching`: scored matching is the
  general surface (`register_op` + `Answer(value=candidate, k=degree)` +
  `declare_annotations`), custom matching belongs to grounded values, and
  the in-language `lib_measure`/`lib_soft` libraries are unchanged.
  `EmbeddingStore.matcher()` went with them; the custom_matchers example
  builds fuzzy, regex and semantic matchers on the public surface.
- Fix the order-dependent take-atom import failure at its root: import
  receipts are dependency-validated cache entries, reusable only while the
  exact source load, digest, and every stored output remain live, so any
  public removal makes the next `import!` rebuild the source contribution
  instead of silently no-opping on a stale receipt. Dependent recompiles
  keep their original load owners, first loads are atomic, failed loads
  restore what they displaced, and removing a space-local shadow re-arms
  already-compiled callers of the inherited definition, across pooled-space
  recycling and both rollback kinds.
- Fix an evaluation loop on grounded operations that cannot compute: the
  retained written call (for example `!(< 1 a)`) is answered as data
  instead of re-entering evaluation until the stack overflows.
- Fix two evaluation-cost regressions the NotReducible protocol introduced,
  each caught by an example the untimed corpus lane had green-masked. An
  equation whose body wraps its own recursive call in a constructor stays
  invertible: the produced structure seeds a bound caller result up front,
  so `(let (plus $A (S Z)) (S (S (S (S Z)))) $A)` peels one constructor per
  level again instead of searching blind
  (`examples/functions/invertpeanoplus.metta`, 0.2 s where it had stopped
  terminating inside 30 minutes). And a result boundary walks a produced
  value for redexes only where one can exist: an operation that masks an
  argument keeps the walk, an Atom-result masker such as `noeval` raises a
  backtrackable escape flag when its compound answer carries written
  material onward, a call whose written arguments contain such a masker
  keeps the walk statically, and every other boundary tests the flag in one
  step. A breadth-first search carrying its queue through a fold stops
  paying the walk over every held state per iteration
  (`examples/reasoning/tilepuzzle.metta`, 6 s where it had crawled past 30
  minutes), while `(id (noeval (+ 20 22)))` still answers `42`. A symbol
  head bound at run time that names no function, builtin, special form, or
  translator rule now builds data directly instead of entering the full
  evaluator per call. And a computed-head call site compiles its argument
  tail once: the emitted branch hands the written tail to the masked path
  only when the resolved head actually masks, and dispatches on the site's
  precompiled values otherwise, instead of re-entering the translator on
  every activation (`examples/performance/matespacefast.metta` ran
  `translate_special_dl` 10.49 million times for 1.57 million data pairs,
  39 s where the pre-protocol tree took 10 s; it now answers in 9.4 s).
- Fix a user `arrow-arity` typing rule's refusal being overwritten by the
  generic arity mismatch, SWI tabling being blocked in pooled spaces whose
  shadow repair had captured `$table_mode/3`, and higher-order calls being
  refused under the dispatcher's own name in the tabling purity walk.


## [1.0.5] - 2026-03-02

### Added

- Released PeTTa v1.0 with smart dispatch, two-stage compilation, function
  specialization, modular libraries, and MORK, MM2, and FAISS integration.

[Unreleased]: https://github.com/trueagi-io/PeTTa/compare/v1.0.5...HEAD
[1.0.5]: https://github.com/trueagi-io/PeTTa/releases/tag/v1.0.5
