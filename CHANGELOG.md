# Changelog

All notable user-facing changes to PeTTa are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The history before
1.0.5 remains available through the repository tags and release notes.

## [Unreleased]

### Added

- Added the engine prelude: the Hyperon-Experimental vocabulary that lived
  in `lib_he` is part of the core engine now, compiled from
  `src/prelude.metta` at startup by the same translator that compiles a
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
  bindings-level custom matcher (`python/examples/integration/`), and two
  production TypeScript servers speaking the remote-space protocol, one
  self-contained and one whose atoms live in a MeTTaScript space
  (`python/examples/integration/typescript_space/`, with the protocol
  itself documented in the website's live section).

### Changed

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

### Changed

- In-place type annotations are spelled `(: $x T)`, plain colon, told apart
  from stored `(: name type)` declarations by POSITION rather than by a second
  spelling. A pattern that is itself a colon expression stays structural, so a
  knowledge base query still retrieves what somebody wrote; below that, only
  `(: $variable expected)` annotates, and nothing looks inside a colon whose
  value slot is not a variable. This follows LeaTTa's mechanised Hyperon
  semantics. Issue #177 proposes `::` "when position cannot distinguish the two
  uses"; it can, and `::` is what MeTTa's own tutorials use for cons lists.

### Fixed

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

### Removed

- Removed `petta.measure` and `petta.matching`: scored matching is the
  general surface (`register_op` + `Answer(value=candidate, k=degree)` +
  `declare_annotations`), custom matching belongs to grounded values, and
  the in-language `lib_measure`/`lib_soft` libraries are unchanged.
  `EmbeddingStore.matcher()` went with them; the custom_matchers example
  builds fuzzy, regex and semantic matchers on the public surface.

## [1.0.5] - 2026-03-02

### Added

- Released PeTTa v1.0 with smart dispatch, two-stage compilation, function
  specialization, modular libraries, and MORK, MM2, and FAISS integration.

[Unreleased]: https://github.com/trueagi-io/PeTTa/compare/v1.0.5...HEAD
[1.0.5]: https://github.com/trueagi-io/PeTTa/releases/tag/v1.0.5
