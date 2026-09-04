# Changelog

All notable user-facing changes to MeTTa are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The history before
1.0.5 remains available through the repository tags and release notes.

## [Unreleased]

## [0.7.2] - 2026-09-04

### Added

- `origin-of` names engine-generated equations. Evaluating a higher-order call
  makes the specializer store a generated equation under a name like
  `twice_Spec_[inc]`, and those atoms save and digest like any other, so a tool
  showing a program what it holds had no way to tell them from source: 19 of the
  238 example programs hold them, 40 of `ch08/15-roman.metta`'s 85 atoms among
  them. `(origin-of twice_Spec_[inc])` now answers `(specialization twice)`,
  naming both the engine as author and the function being specialized, where it
  used to answer `(equation <module>)` exactly as the function it specializes
  did. Every other tier is unchanged.

### Fixed

- A cross-thread wait inside a transaction refuses instead of hanging. A
  transaction reads the database as it was when it opened, so a write another
  thread makes while it runs cannot become visible inside it, and every
  blocking wait waits for exactly such a write. `(let $f (spawn (inc 41))
  (await $f))` answers 42 immediately and never returned inside a transaction;
  the same spawn under a two-second `space_await` answered nothing after the
  full two seconds, which is a wrong answer rather than a slow one. Both now
  refuse at once, naming the reason and the remedy. A channel is unaffected and
  is not guarded, because its queue is not database state.

- A registration rolled back with its transaction no longer leaves the registry
  claiming it. `transaction()` unwinds engine state, and the operation registry
  is the library's own mirror of that state rather than the caller's Python
  bookkeeping, so a failed installer left `registered()` answering True for an
  operation whose reflection rows and type declarations were gone and whose call
  no longer reduced. An installer's own "already installed" check then skipped
  reinstalling a name that stayed dead for the life of the process. Registry
  changes now unwind with the transaction that made them: a replaced
  registration comes back as it was, and an inner commit dies with the outer
  rollback, which is the nesting rule the engine already follows.

- An error carrying an opaque host value no longer replaces itself with a
  complaint about rendering that value. Every `prolog:message//1` clause
  rendered its subject through `swrite/2`, the round-trip writer, which refuses
  a value whose printed form would read back as something else. An opaque host
  handle is exactly such a value, so reporting a failed call threw out of the
  renderer: an operation raising `MettaError("clean")` on a `G(object())`
  argument surfaced `swrite/2: cannot write <py_Box>(0x...) as MeTTa text` with
  no trace of `clean`. Rendering a message is display rather than round-trip, so
  the thirteen message clauses now use `sdisplay/2`, which answers identically
  for every term `swrite` can write and renders the ones it refuses.

- Registering one typed operation in a second space keeps the first space's
  contract. Operation implementations are process-global and the registry is
  keyed by name, but the `(: ...)` and `(annotation ...)` rows an annotated
  signature derives are space-local, so the second registration retired the
  first space's declarations: three rows in space A before, zero after, with
  both operations still reducing and only the last registration site keeping
  its types. An operation now records what it declared in each space, so a
  registration replaces its OWN space's rows, leaves every other space's
  standing, and unregistering clears all of them.

- A function documented without a parameter block is visible to the scoped
  `get-doc` again. `get-doc-function` builds the four-field formal shape and
  matches only `(@doc name desc (@params ...) (@return ...))`, and every
  arrow-typed name was committed to it, so a portable
  `(@doc name (@desc "..."))` made the whole branch fail: `space.doc(subject)`
  raised `EngineError` while the unary `(get-doc subject)` answered the same row
  from the same space. A downstream integration documents 47 arrow-typed
  callables that way and every one of them was invisible. The short shape now
  answers with the description it carries, `(@kind function)` and the real arrow
  type. A name with no documentation at all still raises, so `doc()` keeps
  saying so rather than inventing a placeholder, and two stored documents for
  one name remain two answers.

- `m.limits(inferences=)` and `m.limits(timeout=)` bound a trace. `trace` passed
  no limits to the engine at all, so a bound that stopped `run` on the same
  program left the traced run to finish: measured on `!(loop 2000)` under
  `inferences=100`, `run` stopped at 1,685 inferences with an
  `InferenceLimitError` while `trace` retired 209,322 and completed. `trace` now
  takes the same `timeout=` and `inferences=` its sibling doors take and reads
  the same scoped default. The two bounds stay independent, because they stop
  different things: `max_events` bounds the RECORDING, and a program can retire
  millions of inferences inside a handful of recorded events.

- A context asked for a Space door says where the door is. `MeTTa` carries the
  evaluation doors and `Space` owns storage and introspection, a real split
  that is invisible at a call site: an installer written as `install(m)`
  reached for `m.is_function` and got Python's bare `'MeTTa' object has no
  attribute 'is_function'`, with nothing to suggest `m.self.is_function` one
  attribute away. All 85 storage doors now name the `m.self` spelling, derived
  from `Space`'s own surface so a door it grows is covered the day it lands.
  The refusal stays an ordinary `AttributeError`, so `hasattr` still answers
  False and `getattr(m, name, default)` still returns the default, and it is
  hidden from type checkers so mypy keeps reporting `m.atoms` as
  `attr-defined` rather than typing it away.
- The Python cheat sheet said "most doors exist on both" of the context and its
  space. Twenty-eight of `Space`'s 113 do. It now names which family lives
  where.

- `trace` and `lint` declare what they answer. Both were wrappers that dropped
  the return annotation their implementation carries, so a checker typed
  `m.trace(...)` as `Any` and `llms.txt` was free to describe it as a plain
  `list` of events. It is a `Trace`, which is a list that also carries
  `truncated`, and a caller reading it as a list cannot tell a whole trace from
  one the event bound cut short. The sheet also still named the pre-0.7.1
  default of 1,000,000 events rather than the 10,000 that now applies.
- The `llms` gate reads documented return types. It checked that every taught
  name exists but not what any of them answers, which is why the `trace` line
  described a superseded type for two releases without a red lane. A
  documented `-> Type` is now compared against the live annotation by head
  name, so a sheet may stay more precise than a signature (`list[Derivation]`
  against a live `list[Any]`) while a contradiction fails the run.

## [0.7.1] - 2026-09-04

### Fixed

- Restoring a fast cache costs 58% less. The equation-world codec walked every
  term of the payload three times: the validity pass looked for space
  references, then the whole image was walked again for host objects, and the
  decode walked it a third time rebuilding each node to swap references that a
  program with no child space does not have. One walk answers all three
  questions now and reports whether any reference exists at all, and `none`
  skips the decode outright. On the memory-scale lane `load-fast` falls from
  831,560 inferences to 351,480; on a 2,000-equation cache the validity pass
  falls from 264,121 to 162,068 and the decode from 116,011 to nothing. Neither
  walk rebuilds a node whose children did not change, which is also what the
  save side pays. What remains is one walk of an untrusted payload on load and
  one to locate space handles on save, both of which the format requires.

## [0.7.0] - 2026-09-04

### Fixed

- Declaring one reaction no longer makes every space's bulk atom load 149x
  more expensive. The batched program-atom door steps aside for the per-atom one
  when hooks are live, which its own comment prices at 61.39us an atom against
  2.25us, and the question it asks handed the whole added-atom census to
  `seam:host_add_hooks_idle/2`, whose shim clause matches a SINGLETON reference
  list. The first reaction installs a second `seam:atom_added/2` clause, so the
  census became two references, the clause stopped unifying, and the answer was
  "not idle" for every space -- a forty-equation fast-cache restore went from
  30,274 inferences to 4,496,299 because of one reaction on a space it never
  touched. The bridge hook cannot be filtered by its head, since it is one
  clause with an unbound `Space`, and no host can answer for it because it is
  the engine's own. `seam:atom_hook_ref_idle/2` is the per-reference half:
  whoever installed a hook says whether that one reference is idle for one
  space, and the engine subtracts those before asking the host census about the
  rest, so a host's clause keeps matching the shape it was written for. Back to
  1.02x, with the reaction still firing.

- A trace that reaches its bound answers the prefix and says so, instead of
  raising and discarding it. `max_events` is a COUNT and an event costs the size
  of its term, which nothing bounds, so a trace that refused had already paid
  for the bound it refused at: on `ch22/22-03-search/02-tilepuzzle.metta`, 5,000
  events cost 1.38GB and a downstream renderer measured 50,000 at 5.77GB,
  100,000 above 14GB, and six concurrent renders taking a 60GB machine to 2GB
  free -- every one of them raising and answering nothing. The throw still
  ABORTS the run, which is what bounds the time, and is caught so the events
  already recorded come back; `Trace.truncated` on the Python seat and the
  `truncated` field on the Node seat's `Trace` say when they are a prefix. A
  second bound in cells of the engine's store is what actually bounds the
  memory, since a count cannot: at `max_events=1_000_000` that program now stops
  at 4,035 events and 0.73GB where it exceeded a 4GB cap and died. The default
  drops from 1,000,000 to 10,000, which is what the Node seat already used.

- `llms.txt` names the downstream distribution the way its own `pyproject.toml`
  does, `metta-fabricpc` rather than `metta-fabric-pc`, and stops claiming a
  guarantee it does not carry. The file said its names "are checked against the
  live engine and the real file tree by `check.sh`'s `llms` lane, so a rename
  breaks the build instead of misleading you", and a reader took that as
  universal. It covers call heads, paths and the library roster; the name of a
  distribution published elsewhere has no oracle this repository owns, and a
  lane reading a sibling checkout would go red for that checkout's reasons. The
  sentence says so now, with the case that found it.

- A class that defines `__metta__` is asked, even when it inherits from a type
  the library already knows how to encode. `encode`'s fast table is keyed on the
  exact class, so a subclass missed it and fell to a `singledispatch` that
  resolves by MRO: a `str` subclass reached the `str` encoder and its own hook
  was never consulted. Seven of eight subclass shapes were wrong that way,
  `IntEnum` encoding as a **repr**, and every `StrEnum` `vocabgen.py` emits was
  among them, so `llms.txt`'s "each member IS its wire word and encodes as its
  symbol" was false for every generated vocabulary. `project` had the same
  inversion from the other side: a registration DERIVED from an Enum, dataclass
  or NamedTuple's shape is not an author's opt-in, but it was consulted first,
  so a NamedTuple carrying `__metta__` projected as its constructor expression.
  Both doors ask the hook now, below an explicit `register_type` and above an
  inferred default. Values with no hook are untouched, and the hot path is too:
  the check sits after the exact-class table, and removing the `object`
  fallback's now-dead second call took an unregistered object from 2,221ns back
  to 1,428ns. Reported against the published 0.6.0 wheel by a downstream
  integrator, who saw the `StrEnum` case.

- A process this repository starts now carries a bound that outlives whatever
  started it. `subprocess.run(timeout=)` and a shell driver's own wait are both
  enforced in the parent, so killing the parent leaves the child running with no
  bound at all: two `swipl` children spawned by a repository runner survived
  from 2026-09-01 to 2026-09-03, spinning at 100% for 122 CPU-hours between
  them. The bound moves into a wrapper that shares the child's fate, at four
  places rather than 127 call sites: `check.sh`'s `run()` for every lane whose
  command word is a program, a `bounded` prefix inside the 25 lane functions
  `timeout` cannot exec, `example_parity.py` at `TIMEOUT + CHILD_GRACE` so its
  own `TimeoutExpired` still fires first, and the pytest conftest for a session
  driven directly. `timeout` rather than `PR_SET_PDEATHSIG`, which is set
  through `preexec_fn` (unsafe with threads, and these runners spawn from a
  `ThreadPoolExecutor`) and fires on parent THREAD exit, so a finished pool
  worker would kill a live child. `--preserve-status` is part of it: without
  that flag a signalled child is reported as 124 and its own exit status is
  lost, which three interrupt tests read. `tests/checks/check_process_bounds.py`
  keeps a 38th spawn from arriving unbounded.

- Three repository lanes that had been red are green, and one of them was
  hiding another. `test_the_ruff_configuration_enables_every_family_or_records_why_not`
  failed on a `# noqa: ARG002,D102` written without the comma-space its
  canonical form requires; that assertion fires before the suppression
  burn-down, so the ledger's `D` maximum had been four behind since 9ee20573
  and nothing said so. Respelling the one comment revealed it, and the maximum
  is recorded at 2201 with what accounts for the difference.
  `test_no_tracked_file_cites_an_absolute_workspace_path` failed on an
  interpreter path spelled absolutely inside a `command=` evidence tag in
  `benchmarks/baseline.json`; it reads `$CHECK_PY` now, which is what every
  other `command=` in that file uses.

- The C seat's sanitizer matrix finishes, so `GATE_ONLY=1 sh check.sh` can
  reach its end on this class of machine. `make -C extensions/cmetta sanitize`
  did not terminate: every sanitizer diagnostic is symbolized by
  `llvm-symbolizer`, `/etc/debuginfod/elfutils.urls` points it at
  `https://debuginfod.ubuntu.com`, and it makes a network request for each
  module it cannot resolve locally. That request does not return, so the
  symbolizer sits at 0% CPU and the sanitized process blocks on its pipe
  forever. `timeout 100 make ... sanitize` exits 124; a bare `llvm-symbolizer`
  with one query hangs the same way and answers instantly with
  `DEBUGINFOD_URLS` cleared. `sanitize.sh` clears it now. Nothing is lost: the
  only symbols debuginfod would add are SWI-Prolog's, and the lane's rule reads
  frame #1 for a C-seat source file, whose debug info is local. What was lost
  was the lane, which never reached that rule; it now reports
  `44104 byte(s) leaked in 27 allocation(s)` and `C-seat allocation origins:
  none`.

- `NO_AUTOLOAD=1` boots the engine again, and refuses loudly when it cannot.
  `tests/fixtures/no_autoload_boot.pl` reaches `engine/main.pl` by a path
  relative to its own directory; moving that file into `tests/fixtures/` on
  2026-08-27 added a directory level and left the path one `..` short, as a
  pure rename with no changed line to review. The directive then failed, the
  loader turned that into a warning and carried on, and `swipl` exited 0 having
  defined nothing. `engine/check.sh`'s `no-autoload` GATE, whose command is
  `NO_AUTOLOAD=1 sh test.sh`, reported 233 examples OK while executing zero
  checks, and with stdin open the same boot blocked at the interactive toplevel
  instead of exiting. The path is corrected and the fixture now halts with
  status 2, naming itself and what to fix, so the next move of the file is a
  red lane rather than a silent one. Autoload had not in fact rotted: a serial
  per-example differential over the corpus is 231 files identical under both
  boots, 0 differing. Turning autoload off saves 368.7M instructions of boot,
  33% of it.

- Compiling a head that is not a translator rule costs one indexed lookup
  again. `translate_expr_dl/4` asks about every head it compiles and almost
  none are rules, and the generation guard wrapped the lookup rather than
  following it, so each head paid an extra call for the answer "not a rule"
  that the lookup had already given. The match benchmark returns to its 338,002
  baseline over 600 queries and match-skew to 210,482 over 20, exactly one
  inference each. The guard itself is unchanged and still refuses a rule from
  an earlier life of its execution module.

- The source digest asks whether crypto is present instead of reading the whole
  census row for it. `metta_platform/4` is the host's enumerable view and
  unifies a capability's requirements and the sentence describing what its
  absence costs; a digest choosing between `crypto_data_hash/3` and the SHA
  fallback needs neither, and paid for both on every call. The translate
  benchmark falls from 381,633 inferences to 381,093 and evaluate from 559,371
  to 559,347.

- The engine no longer probes for `library(crypto)` twice at boot.
  `engine/filereader.pl` asks for `crypto_data_hash/3` by name, which records
  the same census status, and every reader of that status runs after it: the
  two digest providers in that file, and `lib_crypto` on import. Boot falls
  from 540,234 inferences to 539,537. Redis keeps its probe, because nothing
  else in the engine mentions it and the census would otherwise be unable to
  answer for a capability it declares.

- The platform census answers a presence question with a presence check. An
  empty import list asks whether the platform HAS a library and takes no name
  from it, and `use_module` answered that by compiling and linking the whole
  thing: `library(redis)` costs 26,939 inferences to load and 2,804 to look
  up, and the engine imports nothing from it. Engine boot falls from 541,743
  inferences to 540,234. A capability whose caller names what it needs still
  loads, so nothing else changes.

- Four gate lanes the fast-cache equation-world work left red are green again:
  the `filereader` to `translator_rules` reach a cache image needs is declared
  in the layering contract, a tuple whose two branches disagreed is annotated,
  a cycle guard that bound its variable in only one arm is restructured so the
  analyser can see the other is unreachable, and the identity twin is re-pinned
  from 3575 to 3564 after `76690d84` gave back most of what `translator_rule/3`
  had cost.

- `test_c_handle_crossing.py` runs its five tests again. It was the third
  consumer left holding the directory `b54dea73` renamed on 2026-08-27, after
  the two finding 26 repaired, and it skipped with "handle.so is not built"
  while that file sat built at the path its own message printed. A new
  `artifact-paths` gate now evaluates every file-relative path expression in
  the tree rather than grepping for a literal, because the same word is stale
  in one place and current in seven others.

- `CHANGELOG.md` no longer ships 134 lines of unresolved merge conflict. They
  landed with the MORK seat merge on 2026-08-28 and survived every gate run
  until 2026-09-03, because `git diff --check` reports leftover markers in a
  DIFF and a marker that is already committed appears in no later diff. Both
  parents' entries are kept, and a new `conflict-markers` gate asks the
  committed tree the question the diff cannot.

- The shared codec corpus now exercises the irregular three-field native
  handle tag, and its inventory check rejects tags without either a case or a
  corpus-owned explanation. The one directional stream-control exemption is
  explicit data, so future tag omissions turn the Python conformance suite red.

- Root gate runs now export a uniquely locked `TMPDIR` beneath
  `ai-tmp/check-runs`. Normal exits remove their run directory; after SIGKILL,
  the next invocation reclaims the unlocked orphan while preserving every
  concurrent run whose lock is still held. Shell `mktemp` fixtures and Python
  `tempfile` users inherit the same disk-backed lifetime without sixteen
  per-caller rewrites.

- The generated MeTTa-library reference now derives its roster from the
  runtime's shared `.metta`/`.pl` discovery rule. Prolog-only `lib_gitimport`
  appears as an honest zero-documentation coverage row, while a library with
  both source halves still appears once and takes its docs from MeTTa. The
  matching `llms.txt` source row now counts library directories instead of
  claiming all 34 have a `.metta` implementation.

- `KERNEL.md` now has a row for every one of the translator's 59 special
  heads, including `return`, which the original eight-head audit also missed.
  A new runtime-derived gate checks both translator tiers, all six stated
  counts, every classification and every reason; its selftest independently
  plants a wrong count and an omitted head.

- The `llms` gate now derives every explicit count in the source table and
  checks coverage in both directions. A corpus-used engine head omitted from
  `llms.txt` now fails beside a documented name the engine does not know, and
  the selftest plants both an omitted head and a wrong count independently.
  Exact-token coverage also exposed eight heads that the earlier substring
  audit had counted only inside longer names; all eight are now named.

- The native-handle round-trip benchmark now loads the chapter-19 shared
  object that `worktree.sh` builds. The benchmark had kept the example tree's
  pre-reorganisation path and silently skipped since the directory moved.

- The `ledger`, `aio-mirror` and `reference` gates are green again. Each had
  been failing on a different commit: `6229e43c` removed the `self.clear()`
  call from `Space.drop` without removing the shrink-ledger row that reaching a
  public method is what earns, `418bed01` moved `Space` without regenerating
  `aio.py`'s mirror, and `d2279ea3` changed docstrings the reference pages
  reproduce. Regenerating them is ordered: `aiogen.py --write` rewrites
  `aio.py`, whose docstrings `reference.py` then reproduces, so the mirror goes
  first and a single pass over the printed remedies does not converge. The
  `generated-artifacts` target now selects all three in remedy order, and a
  structural selftest rejects drift between the alias, source order and
  development guide.

### Changed

- `llms.txt` names all five extension-seam kinds. It listed four, "(event,
  ownership, declaration, service)", and the one it dropped is the largest:
  `host_service` covers 82 of the 199 declared seams. The counts and each
  kind's provenance are stated now, since `engine/ext_points.pl:270-274` gives
  every kind its own `clauses_from/2` rule rather than a shared list.
  `EXTENDING.md` already documented it correctly at its `host_service` section.

- `llms.txt`'s library roster now says what each of the 34 libraries is FOR,
  one clause each, where it had been a bare list of names. A reader choosing
  between `lib_measure` and `lib_soft`, or wondering whether `lib_dict` is a
  dictionary or a space, had to open the sources to find out.

- `KERNEL.md` states what the engine actually holds. It claimed 58 translator
  heads over 50 `translate_special_dl/5` clause-heads and 55 clauses, in
  `engine/translator.pl`; the engine answers 67, 59 and 64, in
  `engine/translator/special_forms.pl`. Eight heads had no entry at all and are
  now named in the opening so the table's silence is not read as their absence:
  `get-atoms`, `metta-thread`, `new-space`, `space-atom-count`,
  `space-contains`, `subtract-atom`, `switch` and `with-seed`. Ask
  `metta_special_form_head/1` rather than the paragraph; nothing reads this
  file, which is how four numbers and a path drifted at once.

- `llms.txt` now names the 64 engine heads the example corpus exercises that it
  had never mentioned, `println!` and `get-atoms` among them, and its sources
  table no longer claims the `llms` lane re-checks counts it does not read. Six
  had drifted: 231 executable programs against 238, 22 numbered chapters against
  20 in both places, five skipped examples described as six, 8 tutorial lessons
  against 9, `engine/reader.c` at 998 lines against 923 and
  `engine/json_codec.c` at 1,201 against 1,219. Every count the lane does check
  was correct. The Python examples row also records how `_common.py` keeps them
  honest: `check` raises rather than asserting, because `python -O` strips an
  assert while the print under it still runs, and `done` refuses its OK line
  when nothing was checked.

- `Space.derivation` now documents its effect boundary: proof premises execute
  for real and their writes accumulate unless the caller selects the existing
  `speculative()` scope. The scope rolls back engine state but cannot undo
  Python, I/O, or callback effects that already occurred.

- Node's `TabledMap` contract now states the swipl-wasm lifetime boundary:
  tabled calls share answers within one `run()`, while a later job uses a new
  threads-disabled SWI engine and recomputes. Persistent cross-run memoization
  remains available only on threaded hosts.

### Fixed

- The Python seat guide now distinguishes literal and bound `Error` data from
  an `Error` produced while evaluating a strict operand, which finishes the
  enclosing call unchanged.

- Fast caches now persist complete equation-world images instead of only the
  root atom list. Bound child spaces, their aliases, and translator rules are
  restored under fresh runtime identities, repeat loads replace the prior
  image, and binary payloads are no longer decoded as UTF-8 during reload.
  Loading an engine-base image reuses matching live prelude registrations in
  that same module without claiming or later retiring them.

- The blocking documentation lane now installs the website's locked VitePress
  dependencies in CI and keys npm's cache with the Node binding and website
  lockfiles. Missing npm or VitePress still gives contributors a local skip,
  but refuses under CI so an unbuilt site cannot report a green docs gate.

- Fast-cache restore now admits a program image through the existing bulk
  equation path and reconciles call-graph analysis once. Recursive content no
  longer turns restore into a growing per-atom analysis loop.

- `duplicate-binder` lint now follows clause-scoped variable identity across
  both `let` and `let*`, including separate binding values. Reusing a plain
  `let` name no longer fails silently without the existing diagnostic.

- Prolog-only Python integrations now use their fully qualified module name as
  the SWI library alias. Distinct dotted modules with the same final component
  no longer share an ordered search path accidentally, while an explicitly
  shared alias remains additive.

- `python -m metta repl` now submits a buffered final form at end of input.
  Incomplete input is reported on stderr instead of disappearing, while the
  interactive command continues to recover from errors and exit successfully.

- Optional `library(crypto)` and `library(redis)` dependencies now participate
  in the platform census before their libraries load. Reduced builds retain
  the five SHA hashes supplied by `library(sha)` and refuse crypto-only or
  Redis operations by the missing capability's name.

- Translator-rule ownership now includes the execution module's monotone life
  generation, and deferred rule bodies are materialized before invocation.
  Reusing a released context name can no longer address its prior predicate
  identity, while an actually stale registry row is refused by generation.

- Engine-owned `&self` and `&metta` spaces now refuse `clear` and `drop`
  before teardown starts. The refusal directs callers to their own context or
  a named space, while ordinary spaces retain both lifecycle operations.

- The specialization differential gate now imports the corpus definition from
  the parity runner and has a planted selftest built from the `wrap-one/sleep`
  arity defect. A disagreement, verifier error, or failed process makes the
  lane red, while a generic plain-call control remains clean.

- Collection closures now treat variables bound by `case`, `switch`, `unify`,
  and `let*` as invocation-local. A list walker no longer carries the first
  element's pattern bindings into later elements and silently selects the
  wrong arm.

- Space-provider conformance checks now strip a hook body's module qualifier
  before selecting and running its leading ownership guard. Registered foreign
  spaces are admitted without executing the operation behind that guard, while
  missing hooks and failing guards still refuse.

- The example parity runner now closes every Python engine and compares test
  verdicts and process exit status as well as answer groups. Teardown failures
  and assertion-status disagreements can no longer be hidden by matching
  answers printed earlier in the run.

- Higher-order specialization now preserves the generic function's call
  arity when substituting a registered function exposes a partial application.
  Applying a variable that holds a native name therefore returns the same
  partial value through generic and specialized paths instead of calling a
  nonexistent narrower predicate.

- Node bridge job identifiers now come from a monotone constant-time
  allocator. Starting jobs no longer scans every suspended job, and an
  emptied job table never reissues an earlier identifier.

- Array constructor registrations now retain a backend's fully qualified
  module name. Installing NumPy no longer silently retargets an earlier
  JAX-backed space, and JAX random construction refuses instead of drawing
  from NumPy's unrelated global random state.

- Translator rules now keep the execution module that owns their body. A rule
  registered in one space therefore compiles calls in every other space, and
  releasing its home retires the global registration before any live
  dependent can resolve a missing body. Release-time support repair skips only
  functions in the dying module. Named-space definitions also withdraw a
  same-named prelude translator rule, matching the existing user-wins policy
  for definitions in `&self`.

## [0.6.0] - 2026-09-02
The `pymetta` line, which is versioned separately from the inherited
upstream tags above it. Published to PyPI as `pymetta` 0.6.0.

### Added

- `Space.effect_plan` answers what a call would write, without running it.



- **`transfer` moves atoms between spaces, and the write family is
  variadic.** `a.transfer(x, y, to=b)` moves one unifying occurrence of
  each atom in one transactional engine crossing, counting the found, so
  a mid-move failure rolls both sides back and nothing is lost between
  spaces. `remove` gained the same variadic face and the same count;
  `eval` batches the way evaluation batches: several terms, one
  crossing, one answer group per term in run()'s own grouping, one bind
  scope over the lot; and `unify` is SIMULTANEOUS when variadic, every
  operand agreeing under one substitution. What `add` accepts, `remove`
  now takes back (bare symbols and grounded values included).
- **`-=` subtracts one occurrence, the grain that makes it `+=`'s
  inverse.** Python's own multiset is `collections.Counter`, whose `-=`
  subtracts the multiplicity given rather than clearing the key, so
  `s += a; s -= a` now leaves the space it found. The drain moved to the
  pattern-shaped door it belongs to, `del s[pattern]`, which takes every
  unifying occurrence in ONE engine crossing rather than one per atom. The
  engine gained `subtract-atom` for the one-occurrence grain beside
  upstream's draining `remove-atom`, so a compiled body's `space -= atom`
  and the Python surface's now mean the same thing, and every door that
  subtracts (`remove`, its variadic face, `transfer`, `-=`) asks that one
  head: it refuses an unbound atom by name instead of reading it as every
  atom at once.
- **The MeTTa context speaks its space's protocols, and `-=` reads what
  `+=` writes.** The context's generated mirror now carries the container
  and write faces (`+=`, `-=`, `|=`, `in`, `len`, iteration, subscript
  match, `del m[pattern]`), delegating each to the process home with the
  in-place trio answering the context itself; and `-=` classifies its
  operand exactly as `+=` does, so a fact stream one door stores the
  other drains in one transactional crossing, where before a tuple of
  rows quietly read as one never-matching pattern.

### Changed

- **Declaring a type costs almost nothing now.** A declared compiled call paid
  46 extra inferences and 1.76 microseconds per call, because the engine
  re-checked what the compiler could already prove. Checks the translator can
  discharge statically are now omitted, under support-graph invalidation so a
  typing rule added later still wins. The same call costs 2 inferences and
  0.25 microseconds. Unknown arguments and reflective calls keep their checks.
- **Several operations changed complexity class rather than constant factor.**
  Stacking K clauses fell from O(K squared) engine crossings to O(K); proof
  projection from O(N squared) to O(N), which is 3.8 seconds to half a
  millisecond at four thousand facts; per-iteration source-position lookup
  from a stack scan to a cached one; `FutureSpace` iteration from a full
  re-snapshot per poll to a watermarked delta; import resolution from a prefix
  search to an amortized constant. Deep atom ordering and proof traversal run
  on a constant Python stack instead of failing at depth 500 and 330.
- The documentation site was rewritten. The API reference publishes prose
  rather than the file-local contract headers it had been reproducing, which
  removed 149 commit hashes and 142 test citations from pages a reader opens.


- **One law lands a rules bundle, whichever door.** `m.add(bundle)`,
  `m += bundle` and `bundle.lower()` now share one landing: equations
  stream in place and the bundle's construction evidence publishes once
  they land. A bundle mixes freely with plain atoms in one `add`, and under
  a `batch()` both the equations and the evidence defer to the flush, so a
  discarded batch publishes nothing where the old eager spelling recorded
  evidence for equations it never landed. The splatted form
  (`add(*bundle)`) stays plain atoms: the splat erases the bundle before
  the door can see it.

- **The eval door pays the dispatch seam once, not twice.** Routing every
  evaluation through the engine's own `resolve_dispatch` (so `lib_memo` can
  bind a cache lookup) had cost +19 inferences per eval because the module
  context was entered once for resolution and again for execution; resolution
  now rides the one execution wrap, returning 11 of the 19. The remaining +8
  is the seam offer and the host loader funnel, the correctness the routing
  bought, priced in each benchmark row's own comment.

- **A combinator member refuses like the engine does.** `overlay()`, `union()`
  and their kin answered `AttributeError` when a backing provider lacked
  `add`, `remove` or `clear`; they speak the capability refusal now, naming
  the provider and distinguishing "does not implement" from "declines".

- **A world counts like the space it froze.** `len(world)`, iteration and
  `atom in world` reach the reified multiset directly on both the sync and
  async seats; `.atoms` remains the longhand.

- **`path()` refuses what its contract excludes.** A bare segment outside
  `str | int | Attr | Key` raised nothing and silently became a `Key`; it
  refuses now and names `Key()` as the opt-in.

- **The module tier is generated from `Space` too.** `metta.run(...)` and its
  sixteen sibling verbs delegate to the default context's self space; nine of
  them had erased their signatures into `*args, **kwargs`, and `metta.trace`
  bounded at 10,000 events where `m.trace` bounds at 1,000,000. The same
  generator now writes both mirrors, so a module door carries the Space
  door's exact parameters, defaults and docstring with a tier note, and
  `metta.trace` follows Space's bound.

- **AsyncMeTTa's 66 mechanical doors are generated from `Space`.**
  Hand-written, they had drifted: fifteen signatures narrower than the sync
  door's, sixteen return annotations vaguer, sixty-four docstrings
  paraphrased, and two runtime refusals of calls the sync surface accepts,
  `await am.type(atom=x)` and `load()` with a `PathLike`. The mirror is now
  written by `tools/aiogen.py` from `Space`'s own source, SQLAlchemy's
  proxy-generation approach, so the async door IS the sync door awaited; the
  six exclusions and four deliberate divergences carry their reasons in
  `tools/aio_divergences.py`, and a gate regenerates and diffs the block.

- **One vocabulary refusal.** Thirteen declaration doors each spelled the
  membership check longhand and had drifted into three variants;
  `_require_vocabulary` is now the one sentence, every refusal byte-identical
  to before, and a door's extra ground clause is a visible `because=` rather
  than an accident. The catalog-declaration helper likewise builds its atom
  from the head, keys and values it is given, so a door can no longer hand it
  a retract pattern and a stored atom that disagree, which is the defect that
  had left stale `(image ...)` rows standing.

- **The C binding installs.** `make install` puts a versioned
  `libcmetta.so.0.1.0` with its `libcmetta.so.0` and `libcmetta.so` links, the
  header, a `cmetta.pc` for pkg-config, and the engine tree under `$PREFIX`,
  with `DESTDIR` staging for a packager. Until now everything built in the
  checkout and every consumer was assumed to be in it: a caller outside had to
  hand-roll `-I`, `-L` and an rpath, and there was no soname, so nothing could
  express which release it had linked against.

  The installed library is a different build from the in-tree one, because it
  bakes the INSTALLED engine's directory rather than this checkout's. That is
  the same bargain `setup.py` makes copying the runtime into the wheel, and
  `$METTA_PATH` still overrides it. `.qlf` files are left out for the reason
  `MANIFEST.in` already gives (a shipped one shadows the source it came from
  and pins the install to the builder's SWI version) while the compiled `.so`
  artifacts go in, unlike the platform-independent wheel's, because this
  install is for one platform by construction.

  `make install-check` is the proof and a gate lane runs it: it installs under
  a real prefix, compiles `tests/install_consumer.c` against nothing but
  `pkg-config --cflags --libs cmetta`, and runs it with `METTA_PATH` unset and
  no rpath into the checkout. Writing that check found a defect in the install
  itself: the baked path is a make VARIABLE, so `make install PREFIX=/a`
  followed by `PREFIX=/b` shipped /a's path inside /b's library. The
  configuration is a prerequisite now, and two prefixes bake two paths.

- **A worked literature-based discovery, which is the case neither half of a
  neurosymbolic system answers alone.**
  `extensions/python/examples/reasoning/literature_discovery.py` reproduces
  Swanson's 1986 result: fish oil may treat Raynaud's syndrome, a conclusion no
  paper in the corpus states. One literature says fish oil lowers blood
  viscosity, another says raised blood viscosity aggravates Raynaud's, and the
  two never cite each other.
  The CHAIN is symbolic, a join a language model does not do reliably and
  cannot show its working for. The vocabulary GAP is neural: the query asks
  about `fish-oil` where every paper says `omega-3`, and no symbolic machinery
  closes that. A class defining `match_` owns its matching inside `unify`, so a
  torch embedding decides what unifies with no registration and the query is
  otherwise an ordinary one.
  The evidence is algebra rather than bookkeeping. Claims and the rule carry
  tags, so the same question under `counting` answers how many independent
  literature paths support the hypothesis (two, through different mechanisms)
  and under `prov` answers which papers, as the polynomial
  `(plus (times (times abc p1) p2) (times (times abc p4) p5))`, whose product
  is joint use and whose sum is alternative derivation
  [Green, Karvounarakis and Tannen, PODS 2007]. `why().render()` prints the
  same derivation for a reader who wants to check it.
  Recorded while writing it: a tagged rule participates in the ANNOTATED layer,
  so a query over one names the algebra it wants. The example says so rather
  than working around it, because a discovered hypothesis without its evidence
  is not worth having.

- **The examples that came from another project are credited, per file and by
  measurement.** 142 of the 251 programs in `examples/` derive from the MeTTa
  sources of https://github.com/patham9/PeTTa at
  `43705f5d9ff8958ffe7f0aa6777fb8477f2401f2`, MIT licensed; the other 109 were
  written here. `examples/ORIGINS.tsv` names each derived file beside the file
  it came from, how much of the upstream body survives with comments ignored,
  and who wrote it there.
  Per FILE, because the obvious version of this is wrong: thirteen people wrote
  those files, and attributing all 142 to the most prolific of them would
  miscredit Roman Treutlein, Nil Geisweiller, Zar Goertzel and ten others whose
  examples are in this directory.
  The list is derived rather than remembered.
  `extensions/python/tools/example_origins.py` recomputes it by comparing
  bodies against the upstream checkout, so a citation cannot quietly stop
  describing the tree, and `test_examples_attribution.py` fails when it does.
  It replaces a README lineage section, and the check that pinned it, which
  framed this repository as a fork; the narrower obligation, that other
  people's work stays credited, is the part that survives.

- **The five effect classes are four decorators, so the classification is a
  name and not a string.** `@m.pure`, `@m.reads`, `@m.writes` and `@m.io` each
  are `m.op` with `effect` filled in, so `transport=`, `name=` and every other
  argument compose with them and there is one mechanism wearing four faces.
  `m.op(effect=...)` stays as the longhand.
  Four rather than five, because `nondeterministicReadOnly` is not something an
  author should have to say: a generator IS nondeterministic and the
  registration already decided that from the function's own code flags. It now
  LIFTS a read-only declaration to that rank instead of refusing it with a
  message telling the author to restate what the library had just worked out.
  The lift only ever raises the rank, so it widens the answer-count claim and
  never weakens an effect claim, and it happens BEFORE the catalog is built so
  the reflected `(effect ...)` row carries the lifted class. Lifting after it
  would leave a generator reflected as `pureStructural`, which is cacheable,
  which is a wrong answer rather than a wordier one. The join that does it is
  the one the async path already used for its own derived floor, generalised
  to take the floor as an argument.
- **`remote.Server` is a context manager.** It owns a socket, an accept thread
  and an engine worker, which is more than any other handle in this library and
  exactly the shape `with` exists for. `metta.space()` and
  `metta.aio.connect()` were already `with`-able; the server, the one whose
  leak on an exception path was silent, was not.

- **The two crossing axes nobody had measured now have numbers, and the numbers
  have an oracle.** `EXTENDING.md` named three independent axes and its cost
  table priced exactly one of them, so a reader choosing between the other two
  was choosing blind. `extensions/python/benchmarks/axes.py` prices both, each
  figure a difference against the same loop with the work removed. Which side
  DRIVES the crossing: 19,557 retired instructions and 12.03 inferences per
  crossing with the engine calling out to a Python `op`, against 96,771 and
  108.07 with the host driving in through `space.eval`, so letting the engine
  call out is about five times cheaper and a loop over many items belongs in
  MeTTa. Two facts fell out of that. The engine-out row reproduces the gated
  extension-cost table's 12.00 independently, which is a cross-check between
  two harnesses; and the source-text door costs the same as the built-term
  door here, so at this call shape the parse is not what costs, the re-entry
  is.
  What a value crosses AS is a complexity class rather than a constant, and the
  fit says so rather than the ratio: fitted by the same `power_fit` the scaling
  gate uses, the transparent ladder's pair slopes climb 0.43, 0.86, 0.98 toward
  1 while the opaque ladder fits an exponent of exactly 0.0 and reports no
  R-squared, which is what a flat curve does. In plain terms four inferences per
  element plus a fixed 17.3, against 12.31 whatever the size, so a thousand-element
  value costs 419 times the instructions to translate and the gap keeps growing.
  `tests/ch18_performance/test_axes.py` holds all of it: the opaque exponent,
  the transparent rate AND its class, since a class assertion alone would admit
  a transparent path costing a hundred inferences an element, and the
  agreement with the gated table. The harness drives one case per process and
  REFUSES a second, because two `MeTTa()` handles share one engine and a second
  case installs a driver head twice, which measures a choice point rather than
  a crossing and looks from outside like a run that never finishes.
- **Every engine document now has a performance section.** `CODEC.md` gains what
  a codec costs, that the cost is the term's SIZE rather than a constant, that
  `o` and `h` are the flat column and only an in-process encoding can use them,
  and the counter warning that bites hardest there: a C wire encoder in this
  tree measured 526x faster on inferences while CPU said 1.8x slower.
  `KERNEL.md` gains what fusing a head costs against moving it, separating
  compile time from run time from the variadic-arity blocker, so its shrink
  target reads as a decision rule. `DEVELOPING.md`'s measurement section is
  rewritten around a table of which counter decides which kind of work.

- **The extension contract now says how a value crosses opaquely, which was the
  one axis it named and never explained.** `extensions/README.md` described
  transparent against opaque and then left the reader to find the mechanism, so
  it has a section for it: what the engine already does (`metatype_of/2`'s last
  clause answers `Grounded` for anything it cannot classify, so a handle is an
  ordinary MeTTa value with no engine change), what it does not
  (`get_type_candidate/2` reaches a host object through `seam:host_object/1` and
  by no other clause, which is why a C `mt_object` answers `%Undefined%` to
  `get-type` where a Python object answers `[datetime, date, Grounded]`), and
  which of the two handle shapes buys which. A blob is `atomic` and not `atom`,
  which is exactly the pre-test in front of the seam, so it can carry a type; an
  id-shaped atom fails that pre-test, and what the seam buys there is the
  metatype, without which the handle reads as an ordinary `Symbol`.
  It also separates two things the axis had run together. Round-trip identity
  holds in all three seats. WRAPPING identity does not: Node interns through a
  `WeakMap` so `G(x) === G(x)`, Python answers `True` for two `py-atom` reads of
  one object, and C allocates a box per `mt_object` call, so two wraps of one
  pointer answer `False` to `==` and fail to `unify`. The C seat's own README
  now says so where its users will read it.
  And it corrects a conflation: `opaque`/`transparent` is the `image-mode`
  vocabulary that `(image <context> <Type> <mode>)` sets, while `registry-image`
  is `expression`/`symbol`/`handle`/`operations`, what a registered type
  presents through `(type-image <Type> <image>)`. The file named the second
  while describing the first.

- **C source lowers into MeTTa equations, and the C seat takes its structs
  seriously.** Two things the surface was missing.
  `mt_lower(m, (twice $x), (* 2 $x))` installs an EQUATION whose body is C
  tokens the compiler saw. That is a different door from `mt_def`, which
  publishes a function the engine CALLS and which must therefore declare an
  effect class because nothing can be seen of what it does. An equation is
  MeTTa: the engine reads it, type-checks it, specialises it, and it is an
  atom in the space, so `mt_match(mt_self(m), E("=", E("poly", V("x")),
  V("body")))` finds it where the same query against an `mt_def` name finds
  nothing. A lowered call also crosses into no host at all.
  The mechanism is the preprocessor. Python lowers by reading a function's
  `__code__` and Node by reading its `toString()`; C has neither at run time
  but has `#`, which is access to the program's own source at the one moment C
  offers it. Nesting survives, so
  `mt_lower(m, (fib $n), (if (< $n 2) $n (+ (fib (- $n 1)) (fib (- $n 2)))))`
  is one line and unbalanced parentheses are a compile error rather than a
  runtime one. Parameterise a body by its operators and it expands to C in one
  mode and MeTTa in the other, so one function is callable from both, which is
  what the other seats' twins buy. What stays out of reach is lowering an
  ARBITRARY existing C function: the body has to be written in the neutral
  form. The seat's constraints ledger had recorded lowering as impossible in
  C; that entry is corrected in place, because it was written after checking
  the run-time route and not the compile-time one.
  Alongside it, four places where C's own struct idioms were going unused. An
  answer is a record, so `mt_rows` binds an `mt_row` carrying the atom, the
  engine's own text, the group and the cursor, which retires `mt_group`,
  `mt_answer_text` and a second walk macro; `mt_each` keeps binding the atom
  alone, the split the Python seat draws between iterating `Answers` and
  iterating `Rows`. `mt_all` answers an `mt_list` of items and length rather
  than an array plus an out-parameter. `mt_ratio_of` answers an `mt_ratio`
  rather than filling two out-parameters. `mt_limit` takes its limits by value,
  so a compound literal says it at the call site and `(mt_limits){0}` means
  what a NULL meant.
  And four C features the surface should have been using: every door that
  hands back a resource is now `warn_unused_result`, so ignoring a cursor or
  an atom is a compile-time warning rather than a leak; `static_assert` checks
  the invariants that were previously only asserted in comments; the header
  `#error`s without C11 rather than expanding to a hundred unrelated
  diagnostics; and `make test` now checks that every `MT_API` declaration has
  a definition, which caught six functions removed by an over-wide edit.

- **The C seat's surface is rebuilt out of C's own idioms, and its verbs are
  now `mt_`.** The first surface worked and was unpleasant to write, because it
  was a transcription: a hand-counted arity stood in for Python's `*args`, an
  out-parameter plus a status code stood in for a return value and an
  exception, and a two-call step-then-read stood in for an iterator. C has its
  own answers to all three and they are old, so this is those, combined.
  The same program, before and after, went from 43 statements to 20.
  `mt_expr("edge", "a", 1, 2.5, V("y"))` counts its own arguments through
  `__VA_ARGS__` and coerces each child by its C type through `_Generic`, so no
  call site carries a length that can drift and no child names a constructor.
  A bare C string in term position is a SYMBOL, which is the one judgement
  here: MeTTa writes a symbol bare and a string quoted, and in C everything is
  quoted, so the default is the one MeTTa writes bare.
  Producers return their value and errors are `errno`-shaped, set on failure
  and not cleared on success, so a run of calls is checked once with `mt_ok()`
  rather than one `if` per call. `mt_each` walks a cursor and closes it however
  the loop is left, `break` included; `mt_one`, `mt_first`, `mt_all` and
  `mt_one_int/_float/_truth/_name` take answers without a walk, with `one` and
  `first` drawing the same line the Python seat draws between `one()` and
  `first()`. `mt_add`, `mt_del`, `mt_eval`, `mt_match`, `mt_atoms`, `mt_count`
  and `mt_wipe` each take a runtime, meaning its `&self`, or a space, chosen by
  `_Generic` the way `tgmath.h` chooses. Reading returns the value the way
  `atoi` does and promotes only where it is lossless, so `mt_float` of an Int
  is that integer while `mt_int` of a Float does not round and an Int past 2^53
  is refused rather than mangled. `mt_show` writes into a per-thread rotating
  buffer so it drops into `printf` with no free, which is `strerror`'s
  contract. `mt_def` takes one designated-initializer struct, so the effect
  class is readable at the call site instead of being the third of five
  positional arguments. `MT_AUTO` releases on scope exit where GCC and Clang
  have the cleanup attribute, and `MT_SHORTHAND` opts in to `S/V/T/N/R/B/E`.
  `mt_bound(it, "y")` answers what the pattern's `$y` reached in this answer,
  under the name the caller wrote rather than a child index, which is what the
  Python seat spells `row.y`; `mt_do(m, src)` runs for effect and discards.
  The prefix is `mt_` and the runtime type is `metta`, because six characters
  typed constantly is its own kind of friction and C's own libraries answer
  that with two to four (`gl`, `vk`, `nk_`, `sg_`, `lua_`). The artefact keeps
  the seat's name, `libcmetta.so` and `cmetta.h`, which is the split the Python
  seat already makes between the dist `pymetta` and the module `metta`. The
  names that cross to the Prolog half, the four `$cmetta_*` foreign predicates,
  the `cmetta_object` blob type and the `cmetta_operation_failed` error term,
  keep the seat's spelling because they are a contract with `bridge.pl` rather
  than part of the C prefix.

- **The Node seat gains spaces implemented in TypeScript, proof trees, the
  reflection verbs, the coordination family and twenty-five subpath satellites.**
  The seat was a faithful core; this makes it a library.

  A space's atoms can now live wherever a program keeps them. `m.attach(name,
  backing)` reads a `Map`, an array, a `Set` or a plain object as a live view
  (read afresh per query, with no publication step), and anything with a shape
  of its own implements `SpaceProvider` and only the methods its backend has.
  Capabilities are DERIVED from those methods, so what a provider cannot do is
  refused by name and its own refusal sentence reaches the caller;
  subscribability is declared rather than derived, because whether a store can
  emit change events is a fact about the store. It rides the engine's published
  `seam:foreign_*` ownership seam over the same trampoline a host operation
  uses, so no new transport was invented for it
  [tested: "answers enumeration, matching and writes through the engine"].
  `metta-node/spaces` composes them: `union`, `readOnly`, `overlay`, `mapped`,
  `diff`, `objectView`.

  `m.why(target)` answers the first proof of an answer and `m.derivation` every
  proof, as a tree whose nodes are a discriminated union on `kind`, which is
  what TypeScript has instead of the four dataclasses the Python side needs, so
  a `switch` over one is exhaustive and the compiler proves it. The
  meta-interpreter is ported from the Python seat's own, cut, soft cut and
  stack charge included [tested: "reads a proof tree as a discriminated union"].

  Beside them: `doc`, `solve`, `cast`, `forms`, `trace`, `disassemble`,
  `runStatus`, the engine's own runtime counters, `m.strict()` and
  `m.limits({ inferences })`. The strict scope runs its source ONCE and judges
  it from what it did, rather than running it to judge it and again to keep it,
  which is what a two-pass strict scope would do to every write inside it
  [tested: "refuses an unreduced directive inside a strict scope, running the
  source once"].

  The coordination family is the platform's own concurrency, because the
  engine's `library(thread)` is absent from a WebAssembly build: `race`,
  `merge`, `parMap` (bounded, input-ordered), `every`, a `Channel` with
  backpressure, and `spawn`. Standing queries get `subscribe` and `LiveView`,
  which counts multiplicity because a space is a multiset.

  Twenty-five subpaths carry the rest, so an unimported one costs nothing:
  `/ambient` is a lazily booted default engine for a program that wants no
  setup line; `/structures` has `AlphaSet`, `PatternMap` and a discrimination
  tree over atoms; `/matching` is unification and alpha keys with no engine at
  all; `/testing` has seeded generators and a shrinking property runner;
  `/vocabularies` publishes all 32 of the engine's closed value sets as
  TypeScript unions, checked against a booted `&metta` rather than against a
  copy [tested: "every vocabulary here matches the engine's own"]; and
  `/strategies`, `/paths`, `/parallel`, `/subscribe`, `/derivation`,
  `/provider` and `/wire` carry the rest.

  The seat also gains a command line (`metta-node run|eval|why|repl|doc|forms`)
  and an error FAMILY: one named subclass per condition under `MettaError`,
  each with its own stable `code`, so a caller narrows by class or switches on
  the code and the two agree.

  Two defects were found and fixed on the way. `Engine.encodeValue` never
  consulted the `ATOM_OF` key, so an operation answering a bare name answered a
  live JavaScript function; and `roundTrip` renamed every variable, because the
  decoder built a name table the encoder was never handed. Both are in
  `ai-node-typescript-constraints.md` with how they were measured.

- **The Node seat closes the rest of the distance to the Python package: how a
  host type crosses, how a library integrates, and a value that owns its own
  matching.** The gap was found by a name-by-name diff of the two surfaces
  rather than from memory, and what remains absent is absent for a stated
  reason rather than an unstated one.

  A registration now names one of four IMAGES, and the four are the engine's
  own: `registry-image` is one of the vocabularies generated from a booted
  engine, so `IMAGES` cannot drift from what the engine knows. `expression` is
  the shaped default; `symbol` crosses as a bare name, which is how an enum
  wants to read, and it runs BACKWARDS too: a bare symbol carries no
  constructor to look up, so every symbol registration is offered the name in
  turn and the first whose `fromAtom` answers claims it; `handle` and
  `operations` cross by reference [tested: "crosses a symbol-image type as a
  bare name, both ways"]. `autoImage(value)` is the rung beneath a declared
  image, `"transparent"` or `"opaque"` in constant time, and an ITERATOR is
  always opaque because measuring or converting one drains it, which is a side
  effect no image choice is allowed to have.

  A package now advertises itself in its own `package.json`, under
  `metta.integrations`, `metta.spaces` or `metta.libraries`, which is the
  ecosystem's own convention rather than a new one. `entryPoints(group)`
  answers the advertised names UNLOADED, so discovery imports nothing and the
  app keeps deciding what loads; two packages advertising one name refuse
  rather than resolving by read order. `discover()` returns integrations in
  INSTALL order from what each `requires`, so a library built on another does
  not have to tell its users the right order by hand, and a cycle refuses
  naming its members [tested: "installs an integration after what it requires,
  and refuses a cycle"]. Beside them `wrapCallable` and `wrapObject` take one
  function or exactly the methods named, and `installReflectionOps` adds
  `(js-attr $o $n)` and the two-mode relation `(js-field $o $n)`, which answers
  a `(name value)` pair whether the name arrives bound or unbound, the second
  mode being what a function cannot offer and a relation can.

  A host value can own its matching, Hyperon's `CustomMatch`: a class with a
  `[CUSTOM_MATCH](other)` method, registered per engine, decides for itself
  what it unifies with, in either operand order, while a variable still binds
  the value whole without consulting it [tested: "decides its own matches once
  it is registered, in either operand order"]. Registration is what turns the
  seam on. Until the first call the matcher carries NO clause for host-owned
  matching, and `define-call` measures 238505 inferences either way, unchanged
  from its pin. That is the difference from the Python seat, which can afford
  an always-present probe because its crossing is a function call; here it is a
  coroutine yield and `seam:matchable_value/1` sits on the matcher's
  ground-comparison path, the hottest there is.

  `EmbeddingStore` puts vectors under keys and searches them from MeTTa, with
  map semantics on write and one contiguous row-major buffer rebuilt lazily
  after one, each row's norm beside it. A zero or non-finite vector is refused
  at the door, because cosine similarity has no answer for either and a
  silently empty ranking is worse than a refusal.

  `definitionFacts(m, fn)` reads what a definition says about itself without
  defining it: the free names, the span, a block comment, and the effect. It
  asks the LOWERING which names a body could not bind itself, because the
  lowering must decide that to compile at all, so the answer is the one the
  equations were built from rather than a second walk that could disagree. The
  effect is the join over the heads the engine declares one for, `unresolved`
  names the rest, and `pure` is conservative: a body reaching an unresolved
  head is never called pure however pure the rest of it reads.

- **Fixed: `superpose-bind` accepted a malformed binding carrier and answered
  the value anyway.** `(superpose-bind ((42 ()) (43 ())))` answered `42` and
  `43`, where the presented-core oracle answers one
  `(Error (superpose-bind ...) "superpose-bind: expected an encoded bindings
  value")` per malformed row. The implementation took the first element of a
  two-element row and restored its second only if it happened to look like a
  carrier, so `()`, `nonsense` and `(bindings junk)` all passed silently.

  A two-element row IS a `collapse-bind` pair, and its second element now has
  to decode: an expression headed by `bindings` whose every entry is one of the
  three shapes the oracle's decoder takes -- `(<- $x v)`, `(<- (:seg $n) (...))`
  or `(seq $n)`. Row shapes that are not two-element pairs keep their old
  readings, because those are the shapes the oracle also passes through: a
  one-or-more-element expression answers its head, and a non-expression answers
  itself.

  The sequence-variable entry shapes are accepted although this engine produces
  neither, because refusing what the oracle accepts is as much a divergence as
  accepting what it refuses -- checked against its own `--min` door, which
  takes `(bindings (seq $n))` and refuses `(bindings (seq x))`, a segment name
  being a variable. The conformance corpus grew from 25 programs to 36, pinning
  every shape that was wrong.

- **A reaction row installs its own write hook, so declaring one works in every
  seat.** `(on <ctx> <pattern> <op>)` was the one declaration whose side effect
  stayed on the HOST: every binding had to call `metta_install_bridges/0` after
  writing the row, the Python seat does it inside a runtime goal string, and a
  binding whose Prolog is statically checked could not do it at all.
  `metta_check_catalog_semantics/3`'s `on` clause now does it, which is the
  same shape a capacity row already had and takes an engine internal OFF the
  host-service floor rather than adding one to it.

  It is there and not in `metta_catalog_note_added/1` for the reason that
  file's own note gives for the events flag: the note walk takes a LIST, so a
  clause added to it is one inference on every `&metta` write, measured at +10
  on the identity twin. The semantics check dispatches on the head ATOM, so a
  clause for one head costs the other heads nothing, and the capability costs
  two inferences per declaration and nothing per ordinary write.

  With the door open, `Space.reacts` and `Space.agenda` land on the Node side.
  The five agenda policies are a production system's conflict-resolution
  strategies under their usual names, and the test proves the policy does the
  work rather than passing by luck: a reaction WITH a priority is a five-item
  row and one without is four, and the engine reads five-item rows first, so a
  mixed pair is already in priority order before any policy runs. Giving both
  reactions a priority makes declaration order and priority order differ.

- **A saga, for undoing what has already committed.** `metta-node/saga` records
  a `(did op args result)` receipt per effectful step and compensates in
  reverse by the `(compensates ...)` rows a program declared. Only operations
  whose DECLARED effect is `writesState` or stronger earn a receipt, because a
  read has nothing to undo. A failed step commits none; `rollback` preflights
  every receipt against a declared compensation before undoing anything; and a
  failed compensation keeps its receipt and every receipt before it, so a retry
  resumes rather than restarts.

  The step is not itself atomic here, and the reason is the one C42 records:
  Python runs each step inside an engine transaction through a host callable,
  and this seat cannot, because it reaches JavaScript by SUSPENDING the engine
  and `engine_yield/1` cannot unwind through a transaction. What remains is the
  classical saga, which is the mechanism sagas exist to provide [source:
  Garcia-Molina and Salem, "Sagas", SIGMOD 1987]. The capture costs one null
  read per operation crossing and no benchmark row moved.

- **A space can declare what it is, hash what it holds, run a term atomically,
  and teach the reader a notation.** Found by writing the surface triage down as
  a table and CHECKING each claimed counterpart rather than asserting it: five
  did not exist, and a whole family had been waved through. Four of the five
  vocabularies these declarations use were already generated in
  `vocabularies.ts`, so the seat published the words with no door to say them
  with.

  `handles(pattern, fidelity)` declares how faithfully a space answers one
  query shape, keyed by SHAPE so a second declaration adds a row and queries
  route by the most specific match: `Exact` licenses pushing the caller's bound
  to the provider, `Partial` and `Sound` stay candidates the engine re-unifies,
  and `Refuse` makes the query a loud error instead of a silent partial answer.
  `covers`, `writes` and `emits` are keyed by space and REPLACE, because two
  rows saying different things about one space is not a stronger claim but an
  unanswerable one.

  `digest()` is a sha256 of the content through the engine's own
  canonicalization, so two spaces agree exactly when they hold the same atoms
  up to alpha, in any insertion order and in any process; a space holding a
  live host reference is refused rather than hashed.

  `capacity(n)` bounds the space through the engine's own admission gate, and
  it is sugar for the claim rather than a consequence of the row, deliberately:
  the pre-add hook takes ONE claimant, and
  `examples/ch15-.../04-admission_pools.metta` writes its own admission judge,
  which a row that claimed the shipped one would lock out. `m.libraryPath`
  registers a directory of sources under an alias, mounting it first because
  the engine runs in a WebAssembly filesystem that cannot see this process's.

  `transaction(term)` runs one term atomically. The body is a term rather than
  a callable, and the engine states the reason rather than this entry guessing
  it: `engine_yield/1 cannot unwind through` a transaction, because this seat
  reaches JavaScript by SUSPENDING the engine where the Python seat makes a
  direct call. Passing a callable refuses with that reason.

  `metta-node/tokens` extends the READER: a full-token regex and the function
  that turns a matching lexeme into an atom, with the callable never leaving
  the host. Worth building rather than recording as unavailable because the
  engine's own platform census reports `regex: present (library(pcre))` for
  this build -- the same census that says `concurrency: absent`, which is the
  evidence behind every thread-shaped exclusion this seat records.

  Beside them `Channel.tryReceive()` and `Channel.queued`, the non-blocking
  take a caller polling several sources needs.

- **Fixed: a conjunction over a space implemented in TypeScript lost every
  answer but the first.** The seat's job held ONE pending iterator for a
  streaming host operation, so a second stream opened before the first was
  drained replaced it and the first could never be resumed. The engine's own
  split opens an inner enumeration while the outer one is suspended, so every
  conjunction over a provider answered its first row and stopped. A native
  space answered all three rows of a three-edge cycle throughout, with no error
  anywhere, which is what made it silent.

  Every stream now carries an identity: the host mints an id, keeps the
  iterator in a map, and the bridge names the id in each pull.
  `extensions/node/src/parallel.ts` already multiplexes live iterators this
  way, so the shape was in-tree rather than invented. A stream the engine cut
  rather than drained is released when the job closes, with `return()` called
  on it so a generator body's own `finally` runs.

  It was found while wiring the planner seam below, not by looking for it. The
  seat's whole provider conformance suite is single-pattern, which is why it
  passed [tested: "answers a conjunction over a provider needing two live
  enumerations at once"].

- **A TypeScript provider can claim a whole conjunction, so its own join is
  reachable.** `seam:foreign_plan/5` is a published extension point this seat
  had never wired, and without it every conjunction is split one pattern at a
  time and re-dispatched per outer row. That is a nested-loop plan, and a
  nested-loop plan cannot reach the AGM bound however fast the backend is: for
  the triangle `R(x,y), S(y,z), T(z,x)` with each relation of size N the bound
  is N^1.5, and no join plan achieves it. So this is not a tuning knob; it is
  the difference between a backend being allowed to be asymptotically better
  and not being allowed to.

  A provider implements `plan(patterns)` and answers which patterns it took BY
  POSITION, plus one row per solution, or nothing to decline. Positions are
  what makes this seat's version simpler than the Python one: a pattern encoded
  to a host and back is a COPY, so a join variable shared across two patterns
  would split in two and the claim would silently lose answers. Python matches
  each returned wire against the wire it sent to undo that, and the engine
  carries a partition check for it; here the partition is exact by
  construction, because positions never leave the engine.

  Wiring it exposed a capability the seat had been reporting wrongly. It
  derived `plan` from a provider's `pushdown` method, but those are two
  different seams: `foreign_pushdown/3` classifies how exactly a provider
  filters ONE pattern, and `plan` is the engine's and Python's word for the
  whole-conjunction join. `pushdown` now has its own capability, and `rules`
  joins as a declared promise that a space's atoms include equations, which no
  method list can derive. `checkSpaceProvider` gains a check that holds a
  planner's claim to the join it replaced, computed by nested loops over the
  space's own atoms, because a claim is EXACT and there is no cheap re-check
  for a join.

- **The Node benchmark's instruction rows stop moving when unrelated source
  grows.** Every instruction pin in `extensions/node/benchmarks/baseline.json`
  is re-measured under a fourth V8 flag, `--expose-gc`, with
  `benchmarks/sampler.ts` collecting the heap to a fixed point at the end of
  setup, outside the measured window.

  The three flags already there make a run reproducible against ITSELF, at
  0.027 percent spread. They do not make it reproducible against a CHANGED
  PROGRAM: `--predictable-gc-schedule` is deterministic given the same
  allocation sequence, and the startup heap is part of that sequence, so
  growing any module the benchmark loads shifted where a collection landed
  inside the window. Measured by a probe that cannot possibly do work: four
  kilobytes of INERT COMMENTS added to `src/theory.ts` moved `host-op` from
  900018262 to 933434511, a 3.7 percent phantom regression from text nothing
  executes. Against the settled heap the same probe moves the whole suite at
  most 0.18 percent, and `host-op` 0.016 percent. This is the layout-bias class
  Mytkowicz et al. name, and a settled starting heap is the cheap half of
  Stabilizer's answer to it [source: Mytkowicz, Diwan, Hauswirth and Sweeney,
  "Producing Wrong Data Without Doing Anything Obviously Wrong!", ASPLOS 2009;
  Curtsinger and Berger, "Stabilizer", ASPLOS 2013].

  Every instruction row moved once and every inference row stayed identical,
  which is the signature of the measurement rather than the work. The rows that
  went UP now carry the collections their own allocation causes instead of
  inheriting an accidental share of the startup heap's. The seat's benchmark
  driver also now names its OWN remedy when the configuration stamp drifts: the
  shared harness suggests a `--update-baseline` flag that belongs to another
  seat's command line, and here only a whole-suite `--update` restamps.

- **The Node seat carries `test.sh` and `bench.sh`, so its tests run standalone
  and its surface is measured for the first time.** `check.sh`'s `node-binding`
  lane now calls `extensions/node/test.sh`, which is the same command a
  developer runs by hand, and a new `node-bench` lane calls
  `extensions/node/bench.sh`. Both keep the seat's skip protocol and neither
  fetches or builds: an absent `node_modules`, an unmade TypeScript build or a
  Python that cannot import `metta.testing` each print the command that
  supplies it and exit 0, because a gate that reaches the network fails for a
  reason that is not the tree. `bench.sh` measures six workloads
  (interned atom construction, the wire codec out and back, a query returning
  two thousand rows, that same ask abandoned after twenty of them, a lowered
  `define`d call, and a generator `op` the engine pulls two thousand times),
  and holds each to a committed pin in `extensions/node/benchmarks/
  baseline.json` through the shared `BenchmarkBaseline`, so one baseline format
  and one regression protocol cover every component
  [tested: sh check.sh node-binding node-bench].

  Which counter decides is a property of the case. Inferences decide wherever
  the engine does the work, read back through the bridge: those four rows read
  the same number in all nine samples of three consecutive runs on a loaded
  box. Where the work is on the TypeScript side the engine's counter cannot
  move at all, so `perf stat -e instructions:u` decides instead, and the three
  cases that straddle the wire pin both because each counter sees one half.
  `answers-lazy` is the sharp one: bridge.pl reports what a job spent as that
  job's LAST event, so an abandoned job reports nothing, and its inference pin
  of ZERO is a statement that the ask really was abandoned: a lazy path that
  began draining would report `query-rows`' 282,622.

  A Node process is not deterministic enough to gate on retired instructions
  unaided, so the instruction rows run under `--predictable
  --predictable-gc-schedule --liftoff-only` and the baseline's configuration
  stamp records them beside the swipl-wasm version, the V8 version, the
  execution route and the seat census. Bare, one engine workload spread 29.5%
  across four rounds; `--liftoff-only` alone took it to 2.6%, naming the
  mechanism as TurboFan tiering swipl-wasm up on background threads inside the
  measured window, and the full set reaches 0.03%.

- **The C seat carries its own `test.sh` and `bench.sh`, and the gate calls the
  same two files a developer does.** `extensions/cmetta/test.sh` builds from
  clean and runs the C suite plus the three examples, which is exactly what the
  `c-binding` lane now invokes; `extensions/cmetta/bench.sh` builds and runs a
  new `c-bench` lane over six workloads a C host actually pays for: the process
  boot to a usable engine, one `cmetta_answers_step`, a term crossing in each
  direction through `cmetta_show` and `cmetta_parse`, an add-and-match pair, and
  an engine error rendered back to C as words. Both lanes keep the seat's skip
  protocol, so a missing compiler, missing SWI headers, missing `perf` or a
  Python that cannot import `metta` is named and skipped rather than failed.

- **Counter pins that survive a foreign boundary: `measure_counters`,
  `observe_measurement`, and the `INSTRUCTIONS` and `CPU_SECONDS` metrics.**
  Inference counters are blind across the C boundary because foreign code
  retires no inferences at all, and this tree has the failure on record: a C
  wire encoder measured 526x faster on the inference counter while CPU time
  said it was 1.8x SLOWER. `measure_counters` runs one `perf stat` for several
  events and returns each run's counters and its standard output;
  `observe_measurement` gives CPU time the same two-sided declared band
  instructions already had, so a drop still fails as a stale pin. Every C-seat
  case is decided by `instructions:u` and CPU time PAIRED. A baseline document
  now also takes its policy prose from its runner's source, so a seat whose
  deciding counter is not the default one cannot ship a file that states the
  opposite of its own rule.

- **The engine has a benchmark suite of its own, measured with no host in the
  process: `sh engine/bench.sh`.** The only benchmark suite in this tree was
  `extensions/python/benchmarks/`, and every case in it reaches the engine
  through the Python host, so an engine change's cost could only be observed
  with a host's cost added to it and a reader or translator regression arrived
  diluted by whatever the harness spent around it. Each sample here is a fresh
  `swipl -g "metta_bench:bench_run(<case>)" -t halt engine/bench.pl` and
  nothing else. Seven cases, each with its own committed pin in
  `engine/bench-baseline.json` and its own paragraph there saying why that
  workload: `boot` loads the engine the way `engine/main.pl` does, `parse` and
  `parse-prolog` read `engine/prelude.metta` 25 times through the shipped door
  and through `parse_metta_source_prolog/2`, `translate` compiles
  `lib/lib_pln/lib_pln.metta`'s 77 equations over 49 names, `match` and
  `match-skew` run the selective and the skewed query shapes
  `examples/ch18-performance/18-01-larger-workloads/01-scale.metta` defines
  over a space its own `addK` fills with 50,000 atoms, and `evaluate` runs
  `map-flat` over `(range 50000)` from that chapter's `02-holbenchmark.metta`.
  The workloads are the tree's own text rather than strings invented for a
  benchmark, and the baseline digests every one of them, so editing a corpus
  file REFUSES the comparison naming the file instead of reporting a move the
  engine did not make.

  Inferences decide, because they are deterministic under load: every case read
  an identical count in all three samples of three consecutive runs at loadavg
  10.8 to 13.3. `perf stat -e instructions:u` rides along as the second
  counter, measured over the same region through perf's control descriptors so
  it excludes the boot every case would otherwise carry; the `parse` case needs
  it, since with `engine/reader.so` present that door retires 152 inferences
  for 25 reads and the work is all in C. Wall time is recorded and decides
  nothing. Comparison, the two-sided band, the configuration stamp and the
  atomic re-pin are `metta.testing`'s, imported rather than reimplemented, so
  there is one baseline format and one regression protocol across the
  repository. `sh engine/bench.sh --update-baseline` re-pins and prints what
  moved and by how much
  [tested: engine/bench.sh].

- **`engine/check.sh`, which did not exist.** The root gate's component loop
  names `"$HERE"/engine/check.sh` first and `[ -f ... ] || continue` had been
  swallowing its absence, so the largest component was the one with no lanes of
  its own. It carries the `engine-bench` lane
  [tested: engine/bench.sh].

- **The MORK backend owns tests, lanes and benchmarks of its own.** It had
  none: what tested it lived in
  `extensions/python/tests/ch19_spaces_backed_by_anything/test_mork_space.py`
  and `tests/prolog/suites/seams/extensions.plt`, so the seat could be present
  and broken in a configuration neither of those exercised. It now carries
  `check.sh` (three lanes the root gate discovers and sources), `test.sh` and
  `bench.sh`. `tests/mork_seat.plt` holds twenty-five tests over the three
  declared builtins, the claim over the `&mork` namespace, and the discipline
  that makes a space this seat does not own leave every ownership seam and
  every builtin by FAILING rather than refusing, so the next provider's clause
  runs. `tests/test_missing_artefacts.sh` boots a real engine over a seat
  pointed at an artefact that is genuinely absent, rather than staging the
  records an unbuilt tree would hold, and requires the boot to write zero bytes
  to both streams and `!(require-extension! mork)` to name the seat, the file
  and the build command.

- **`extensions/mork/bench.sh`, ten cases at three sizes against a committed
  baseline, deciding on `instructions:u` inside perf's own control window.**
  The window is what makes the numbers usable: measured as whole-process
  differences instead, one operation read +1,592,533 instructions under an
  inherited environment, +774,281 under `LC_ALL=C` and -714,626 under
  `LC_ALL=C.UTF-8`, three stable modes selected by the environment block rather
  than by any work. Inside the window the same operation repeats within 0.018%,
  and thirty of the thirty-one committed rows move under 0.25% across four
  runs. The suite answers what a storage backend has to answer, which is a
  comparison: the batch door is worth three of the per-atom door at every size,
  MORK costs a flat 2.2x a native space to write and 10.9x to enumerate, and a
  selective query splits by which position is bound. A bound first argument is
  a path prefix and costs a flat 10.3x; a bound last argument is a constraint
  MORK can only check after walking, and that one goes 46.6x, 133.8x and 611.5x
  as the space grows 500, 2000, 8000.

  Inference counts are pinned beside those, as the Prolog-side cost they
  honestly are, and CPU seconds are recorded through the harness's new
  `BenchmarkBaseline.observe_cpu`. The pairing is not decoration: SWI's
  inference counter retires nothing for work inside the Rust library, and this
  suite has the demonstration in one row. `mork-match-first` and
  `mork-match-last` both read 133 inferences per query at 8000 atoms while CPU
  reads 7.4 microseconds against 342.7.

- **One area per extension on the site, each publishing that seat's own
  documentation from its own folder.** `/extensions/` introduces the seat model
  (a folder carrying an `extension.pl`, with the two `entry/2` roles saying
  which direction it faces), and each of the four seats has an area:
  `/extensions/node` and `/extensions/cmetta` include the READMEs those folders
  already ship, `/extensions/mork` includes a README that seat did not have,
  and `/extensions/python` routes to the tutorials, guide, integrations,
  live-systems, reasoning and reference sections, which are that seat's
  documentation and always were. Adding a seat and forgetting its page is now a
  failing check rather than an omission nobody sees
  [tested: test_every_extension_has_a_site_area].

- **The site publishes the engine documents: `EXTENDING.md`, `KERNEL.md`,
  `CODEC.md` and `DEVELOPING.md` are an Engine section rather than files you
  only meet by browsing the repository.** Everything the site carried was
  written from the Python surface looking in; how to extend the engine, which
  forms the translator gives meaning to, the wire an atom crosses on, and how
  to work on the repository were reachable only from a checkout. The four pages
  INCLUDE their root documents through VitePress's `@include` rather than
  copying them, so there is still one copy of each and the published text is
  the committed one, which matters most for `EXTENDING.md`, whose cost table
  the `extcost` gate pins, and `KERNEL.md`, whose head tables the `plunit`
  lane's `translator_derived_forms` suite keeps true. Each page carries its
  source document's own file name, so the relative links those documents write
  between themselves resolve with no edit to the sources, and a `rewrites`
  entry publishes it under this site's lowercase spelling
  (`/engine/extending`). Five pages that shipped reachable only through the
  search box are in the navigation now: `guide/contract.md`,
  `integrations/sqlite-blobs.md`, and the generated reference pages for
  `metta.paths`, `metta.events` and `metta.answer`, the last of which the
  reference index had lost as well.
- **The documentation site is a gate lane, `docs`.** Three config headers and
  every page header claimed `[tested: npm run docs:build]` and no lane had ever
  run it, so a dead internal link could ship. It does not fetch (the rule the
  Node lanes already follow), and says which step is missing instead when npm
  or `website/node_modules` is absent. Two checks in the `pytest` lane hold the
  structure on every machine, node or no node: every `@include` resolves, which
  VitePress itself does not check (its include is fail-open, so a renamed
  source publishes an EMPTY page under a green build), and every page is
  reachable from the navigation. A page that is unlisted on purpose says
  `navigation: false` in its own frontmatter and the check passes; the
  exemption lives in the page rather than in a list, so it is visible to
  whoever opens it and leaves when the page does.

- **Space ownership is engine data, and a second claim on a live name is
  refused naming both owners.** `seam:foreign_space/1` is a CONDITION on a
  name rather than a list, so nobody could see a collision: the engine could
  not enumerate claimed names, and a provider could not see its peers without
  naming them, which is the one thing the seam exists to prevent. The three
  shipped providers each kept a private registry (`mork_owns_space/1`,
  `metta_py_foreign/1`, `redis_space_conn/7`), and two of them matching one
  name resolved by clause order, which is `msort` over folder names, so an
  atom landed in whichever store loaded first with nothing said.
  `metta_claim_space/2` and `metta_disclaim_space/2` are the missing half, and
  `metta_space_claim/2` is the table, enumerable at last. A claim's extent is
  a name or a whole namespace as `prefix(P)`, because MORK's ownership
  genuinely is `every name beginning &mork` with no per-name attach point;
  two extents collide when they intersect. Linux's char-device registry is the
  same object and settled it the same way, a claim being a range, a duplicate
  `-EBUSY`, and `/proc/devices` the enumeration (`fs/char_dev.c`,
  `__register_chrdev_region`). Redis claims in `redis-attach` before it opens a
  socket and releases at `redis-detach`, the Python seat claims as it registers
  a provider and releases as it unregisters, and MORK claims its namespace when
  its provider loads. A same-owner re-claim is idempotent, releasing a claim
  that is not there passes, and releasing another owner's refuses.
  Nothing on a space operation's path reads any of it: the door is for
  claim-time refusal and enumeration, and three space workloads of 2,000
  operations each cost identical inferences before and after.

- **`!(require-extension! mork)`: a library says which seat it rests on, and
  the refusal is transitive.** A `lib/` module that is the on-demand half of a
  boot-loaded seat had no way to say so, and `lib/lib_mm2/lib_mm2.metta` is the
  case: five operators over `&mork` calling MORK's own builtins with zero
  presence checks, so on a tree where the FFI was never built each of the five
  failed at call time with nothing naming the cause. That is exactly
  PostgreSQL's `pg_stat_statements` shape (a preloaded C module plus a
  per-database `CREATE EXTENSION`), and Postgres answers the broken half by
  name (`pg_stat_statements must be loaded via shared_preload_libraries`).
  `require-extension!` is that answer here. It answers the unit when the seat
  is loaded and otherwise refuses with the cause read out of the loader's own
  `metta_extension_unmet/2` records, followed as far as the needs graph goes:
  a need of kind `extension(Other)` is resolved into `Other`'s own cause, so a
  chain two seats deep is one message, and the walk carries a seen list so a
  cycle is reported rather than looped. The message ends in the remedy, the
  seat's own `build.sh`:

  ```
  'lib/lib_mm2/lib_mm2.metta': extension mork is required and not loaded:
  artefact extensions/mork/mork_ffi/target/release/libmork_ffi.so is absent
  (run extensions/mork/build.sh) (while loading MeTTa file)
  ```

  The requiring file comes from the file loader's own frame rather than from
  the form, which is PostgreSQL's MESSAGE-and-CONTEXT split and Node's
  `Cannot find module` plus `Require stack`; a require typed at a REPL names
  only what is missing. Three causes are told apart because their remedies
  differ: a need that failed, a seat whose control file is there on a boot
  that carried no `extensions` token (the pure kernel), and a name with no
  control file at all.
- **The platform census covers the engine's SWI packages: `regex`,
  `compressed-sources` and `fast-cache`.** `metta_platform/4` answered for
  `concurrency`, `deadlines` and `subprocess`; the four packages
  `engine/filereader.pl` and `engine/parser.pl` loaded unconditionally were
  outside it, so an SWI without one of them failed with SWI's own error and
  nothing said what was lost. Withholding `library(pcre)` printed four ERROR
  pairs, one per unguarded load, and an `(import! &self (library lib_regex))`
  came back wrapped in a transcript of the loader's `source_sink` error.
  Each capability now loads through the census and refuses by name where its
  absence bites: `regex` at the library's own `metta_requires(regex)`
  declaration, at `(register-token! ...)`, and at
  `(import_prolog_function re_replace)`, which used to answer "no predicate
  named re_replace is loaded, so registering it would compile every call to it
  into a partial application rather than failing" and now names the capability
  as well, because the census records the names its own load could not import;
  `compressed-sources` at the one gzip door every `.gz` read and write goes
  through, naming the file, with a plain path paying nothing; `fast-cache` at
  the two host doors the cache has. A row may rest on several libraries, which
  is what `fast-cache` needs, and `present` means every one of them resolved.
  What an absence costs differs by row and the census says so: `regex` takes
  forms away, compression takes one file FORMAT away while the same program
  uncompressed still loads, and the fast cache takes no MeTTa form at all,
  because the engine never reads a cache of its own accord and a build without
  it loads, runs and reparses exactly as a build with it does when no cache was
  written.

- The reduced-platform harness takes libraries away one set at a time.
  `run_reduced_platform/3` withholds EXTRA libraries beside the default four,
  so a capability can be tested on a real SWI that genuinely lacks its library
  rather than on a planted absence; the default set stays the WebAssembly four,
  and `tests/prolog/suites/seams/platform_capabilities.plt` memoizes one child
  boot per set. The child now decides each probe from the census, so one report
  serves every set and a guard that stops firing reads as `unexpected` instead
  of passing quietly.
- **The writer has a C implementation now, beside the reader's.** The reader
  half of `engine/parser.pl` has had `engine/reader.c` since the compiled-reader
  spike; the writer half had nothing, and writing is on every answer that
  crosses to a host, every atom a space digest hashes, every atom a save
  refuses or stores, and every line the MORK bridge sends. `engine/writer.c`
  ports three Prolog layers into ONE walk: `swrite_mode//2`'s structural emit,
  `metta_finite_float_codes/2`'s arbiter float layout, and
  `metta_unwritable_walk/2`'s round-trip guard. The Prolog remains the
  specification, the custom-token path and the fallback, exactly as it does for
  the reader; `engine/build.sh` builds both units, `engine/.gitignore` ignores
  both shared objects, and `METTA_C_WRITER=off` or an absent artifact keeps
  every write on the DCG.

  Measured in one worktree, the control being the same tree with `writer.c`,
  `metta_token.h` and this branch's `parser.pl` removed and the engine
  re-warmed, the MORK backend loaded on both sides:

  | door, 3518 corpus forms | instructions:u | CPU |
  |---|---|---|
  | `swrite/2` | 772,513,255 to 123,419,377, 6.26x | 47.77ms to 6.68ms, 7.15x |
  | `sdisplay/2` | 595,393,404 to 120,511,378, 4.94x | 35.84ms to 6.80ms, 5.27x |
  | `metta_unwritable_symbol/2` | 174,350,260 to 105,304,395, 1.66x | 8.68ms to 6.06ms, 1.43x |
  | `swrite_with_names/3` | 984,008,827 to 412,826,225, 2.38x | 61.71ms to 23.37ms, 2.64x |

  and on the pinned benchmark rows, `space-digest` 1,400,321 to 920,299
  inferences with 2,203,843,001 to 1,472,910,570 instructions:u,
  `save-load-fast` 2,287,062 to 1,526,592 with 3,156,360,120 to 3,020,017,567,
  `save-load-metta` 1,386,110 to 1,005,690 with 3,126,713,473 to 3,030,397,654,
  and the `mork-write` scaling family halved at every size with its linear
  class intact. `with_names` moves least because `named_print_term/3`'s copy,
  numbering and epoch spellings stay in Prolog. Both meters are quoted because
  foreign code retires no inferences: the counter alone once read a 526x win in
  this tree over a 1.8x CPU loss, so a C path priced by inferences is priced by
  the wrong instrument.

  Three hazards decided the design.

  FLOATS. Every float leaf takes SWI's own shortest-round-trip digits, from the
  same `PL_get_text(CVT_FLOAT)` call `number_codes/2` makes, and reshapes them
  into the arbiter's layout as text. Nothing re-derives a decimal: the digit
  selection has a documented trap, where the closest candidate at a given
  precision falls outside the rounding interval for 46 of the 2098 powers of
  two, and the port sidesteps it by not doing that work. The lane checks every
  power of two in the binary64 range and both signs, plus 40,000 random
  magnitudes, plus `1.0`, `0.1`, `1e20`, `1e-320`, `-0.0`, `5e-324`, the
  positional-to-scientific boundary at `1e16`, and the non-finite spellings.

  ENCODING. The writer never asks the locale anything. It reads an atom's text
  through `PL_atom_nchars` (in place when the atom is Latin-1 and ASCII, which
  is every ordinary symbol) or `PL_atom_wchars`, transcodes to UTF-8 itself,
  and classifies against `engine/metta_token.h`'s own tables rather than
  `code_type/2`, whose whitespace class moves with the locale. The battery
  carries the MM2 operators `＋` and `－`, Japanese and accented names, an
  embedded NUL, and a symbol built around EVERY codepoint the engine's own
  boundary table lists; the whole suite is run again under `LC_ALL=C` and
  answers identically.

  MEASUREMENT. Priced with `perf stat -e instructions:u` and CPU time,
  minimum of three, both sides in the same worktree, because instruction
  counts here are tree-location sensitive and inferences are blind across the
  boundary. One correction landed from this: an early control read a
  configuration WITHOUT the MORK backend, because `worktree.sh` had linked its
  artifact from the main checkout and a sibling's rename left the link
  dangling. That attributed 80,038 inferences of backend cost to a stale pin.
  The artifacts are copied into the worktree now rather than linked, and
  `benchmarks/configuration.py` carries `c_writer` so a tree without the
  artifact can no longer compare against C-writer pins at all.

  What the C path does NOT take, it hands back, and the Prolog writer answers
  instead: an improper list, a rational, a non-marker compound or an opaque
  host value in display mode, a term holding more than 64 distinct variables,
  and a float or bignum whose SWI spelling outruns the file's scratch.
  Approximate bytes are never emitted. `tests/prolog/suites/reader/writer_c.plt`
  is the differential and it is two-sided: 3518 corpus forms and 213 adversarial
  shapes through five modes each, 8 public doors over the same 3731 terms,
  1880 distinct corpus symbols plus 143 generated spellings through the
  writability question, 44,196 float spellings and 4,000 bignums; a decline
  counter that fails if the C path stops answering the corpus; a planted
  one-byte divergence that must be caught; and a check that the reference run
  really leaves the C writer, because every reference in the file is the same
  door with `parser:metta_c_writer_active/0` retracted. The planted divergence
  was also done for real, by making the C emit two spaces between list elements
  instead of one: 5 of the then-12 tests turned red on the first corpus form,
  naming `ok("(+ 40 2)")` against `ok("(+  40  2)")`.

  `engine/metta_token.h` is new and both C units include it: the 25-codepoint
  whitespace table, the UTF-8 codec and the whole-token number matcher now have
  ONE C transcription instead of one per direction, which is what
  `metta_token_boundary/2`'s own comment asks for on the Prolog side.
- **JSON is answered in C, and library(json) stays the specification.**
  `engine/json_codec.c` reads and writes JSON directly to and from Prolog
  terms, behind `engine/json_codec.pl`, the one JSON door this repository now
  uses: the Python binding's network codec and `lib/lib_json`'s MeTTa surface
  both go through it, so there is still exactly ONE JSON implementation for
  the whole system, which is why `orjson` was removed in the first place.

  The cost it removes was measured before it was written. SWI's
  `library(json)` is mostly Prolog -- only four of its predicates are foreign,
  `json_read_number/3`, `json_skip_ws/3`, `json_write_string/2` and
  `json_write_indent/3` -- and its reader takes strings apart one character at
  a time: an SWI profile of `json_read_dict/3` over the shipped 25,017-byte
  `json-wire` payload puts 35.1% of self time in `system:get_code/2` and 21.2%
  in `json:json_string_codes/3`, and draining that document through
  `get_code/2` alone costs 689 of decode's 1,424 microseconds. Its dict door
  also parses the whole document into the classic `json(Pairs)` shape and then
  converts that to dicts. Measured on the shipped payload, per call, minimum of
  five windows: reading a dict 1,313.5 to 117.0 microseconds (11.2x), writing
  one 894.9 to 156.3 (5.7x), reading the classic shape 1,211.6 to 136.8
  (8.9x), writing it 809.7 to 177.3 (4.6x). End to end the `json-wire` round
  trip falls from 2,627.85 to 482.97 microseconds of process CPU, 5.44x, and
  its retired instructions from 125,984,226,952 to 22,670,111,346 -- not the
  33x that row's comment recorded, and not reachable: the janus crossing alone
  is 207.77 of those microseconds, so a free codec would still leave a ceiling
  of 12.6x. CPython's own C-accelerated `json` does the same round trip in
  137.52 microseconds without crossing anything.

  The MeTTa surface gains less, because less of its cost is JSON:
  `(json-decode ...)` of the same document falls from 3,186.3 to 2,224.0
  microseconds, 1.43x, since minting a space per object and adding an atom
  per pair is 89% of what is left; `(json-encode ...)` falls from 1,884.1 to
  717.3, 2.63x.

  Nothing here approximates. The C path answers a document EXACTLY as
  `library(json)` answers it or it FAILS, and a failure is the seam's signal to
  run the Prolog implementation, so every JSON error term, message and stream
  position is the one this repository has always produced. What it declines is
  pinned as its own test: a lone surrogate, a number outside strict JSON syntax
  (`01` and `1.`, which Prolog's own number parser reads its own way), a
  trailing comma, text after the value, a duplicate key, nesting past 1,000,
  a non-finite or rational number, and any term the writer does not recognise.
  Numbers are converted by SWI itself wherever exactness is at stake:
  `PL_put_term_from_chars` for an unbounded integer, exactly as SWI's own
  `json_read_number/3` does, and `PL_get_nchars(CVT_NUMBER)` for writing, which
  is the same `format_float()` call `write/1` makes -- 300,000 random doubles
  and 12 edge cases produced identical text through both.

  `tests/prolog/suites/libraries/json_codec.plt` is the gate, and it compares
  the two implementations inside ONE process rather than against a remembered
  answer: 125 hand-written documents covering structure, every escape, the
  surrogate cases, the number boundaries and the hazard set, plus 800 generated
  documents whose strings draw from control characters, the two escaped
  characters, ASCII, Latin-1, the basic plane and the astral plane, each read
  and written through both paths in both shapes. It also pins which documents
  the C path ANSWERS, because a C path that quietly declined everything would
  satisfy every agreement test in the file while measuring nothing. The same
  comparison over all 318 files of `nst/JSONTestSuite` reports zero
  disagreements in either shape or either direction, and the C reader answers
  93 of its 95 must-accept files (the two it declines are the duplicate-key
  cases this codec refuses anyway).

  Two of `library(json)`'s own extension points would break that agreement if
  anything used them: `json_dict_pairs/2` replaces a dict's key order and
  `json_write_hook/4` replaces how a term is emitted, and the C writer knows
  neither. A process that defines one gets the Prolog writer for everything
  rather than two writers that disagree.

  `METTA_C_JSON=off`, or a missing `engine/json_codec.so`, keeps every
  conversion on `library(json)`; both configurations run green.

  `engine/build.sh` now discovers the C units beside it instead of naming
  `reader.c`, so a second one needs no edit there.

- **The example corpus's teaching order is now CHECKED.** The law is that a
  file may use only constructs introduced at or before its own number, and it
  was previously a statement in a design note that nothing enforced. Three
  pieces enforce it. `tests/prolog/example_constructs.pl` reads a `.metta` file
  through the engine's own parser and keeps only the heads the engine
  publishes, asking both `builtin_fun/1` and `metta_special_form_head/1`
  because neither answers for the other: the first does not know `if` or
  `case`, the second does not know `+` or the `#`-prefixed arithmetic family.
  `tests/data/syntax_introductions.txt` holds the introduction table, 208 rows
  in teaching order; it is checked in rather than derived, because a table
  derived from the corpus makes the law true by definition and catches nothing.
  `tests/checks/check_cumulative_syntax.py` compares them and also refuses a
  stale row, a row placed before its earliest use, a row naming something the
  language does not have, and a violation of the spine's measured dependency
  floor, where every file using A also uses B and B is the more common, so B
  may not be introduced after A. That floor holds over all 1,280 such pairs
  today. `--write` regenerates the table, so accepting a deliberate change to
  the order is one command and a reviewable diff.
  The lane carries a permanent negative control INSIDE the corpus,
  `examples/ch01-getting-started/_fixtures/01-reaches-forward.metta`, a
  chapter-1 file using a chapter-15 and a chapter-22 construct, and fails if it
  ever stops catching it. Its selftest plants eight violations, one per rule,
  each asserted against the words its own rule says, because a gate that
  catches the wrong thing for the right input is the failure that a plain
  "something was reported" check misses.
  `:` and `->` are outside all of this: the engine publishes them as neither a
  builtin nor a special form, so the law does not reach type declarations, and
  a hand-written second vocabulary would drift.

- The evidence gate reads the Node binding too. `tests/check_evidence_tags.py`
  scans `bindings/node/*.pl` and `bindings/node/src/**/*.ts`, collects the
  names a `node --test` suite declares (its `describe` and `it` titles), and
  `tests/evidence_runners.py` models the npm indirection, so a lane running
  `npm run test` inside a package is understood to run that package's
  `test/*.test.ts`. A `node --test` case names itself in PROSE rather than in
  an identifier, so a claim may now QUOTE the name it points at and the
  quoted name may wrap across lines the way any comment does. Without all
  three, every evidence claim in the binding read as unbacked and the gate
  that exists because thirteen claims once named tests that had never existed
  could not see a whole binding.

- The Node binding is now a TypeScript LIBRARY rather than a transport, the
  sibling of the Python `metta` package. Atoms are interned, so `===`, `Set`
  and `Map` are structural without any of them being reimplemented; `S`, `V`,
  `G`, `_`, `seg` and `fn` are the name doors, and a TypeScript identifier
  reaches the meaning layer through TypeScript's own casing, so `S.carAtom` is
  `car-atom` and `function balanceOf` installs `balance-of`. The map fires only
  on a plain lowerCamelCase identifier, so `Number`, `%Undefined%`, `prime?`
  and `car-atom` are each exactly themselves.
  An ask is lazy and thenable: `for await` streams it, `await` collapses it,
  `.one()` is exactly-one and `.find()` is at-most-one, and leaving a loop early
  closes the cursor, so an unbounded generator is safe to walk. A deadline is
  `AbortSignal` in the options position.
  A space is a collection and means by `add`, `delete`, `has`, `size` and
  `clear` what `Set` means by them; `match` answers rows keyed by the pattern's
  own variable names, and a space is named by an ATOM, so a parametric space is
  a handle like any other.
  Three definition doors. A plain function's own source is LOWERED into one
  equation, so `function findDivisor(n, d) { if (d * d > n) return n; ... }`
  becomes `(= (find-divisor $n $d) (if (> (* $d $d) $n) $n ...))` and a call
  costs no host crossing at all, while the same body still runs in TypeScript.
  A generator body is TRACED once with symbolic arguments, where `yield*` asks
  a goal and `yield` emits an answer, so a conjunction becomes a nest of matches
  and several emissions become several clauses. And `op` keeps host code as
  host code: a plain body answers once, a generator body is nondeterminism from
  JavaScript pulled one answer at a time, and an async body is awaited from the
  middle of a reduction.
  `using` carries the resource-shaped constructs: `m.limits({ stack })`,
  `m.stats()` with the inferences, crossings and replays counters, and
  `m.world(space)`, a draft that commits its whole delta inside one engine
  transaction and restores for free. Live queries, a state cell, the schema
  door with Standard Schema interop, and the library tier round out the
  surface.
  A host operation reaches JavaScript through SWI's own engine coroutine,
  `engine_yield/1` and `engine_post/2`, rather than through `library(wasm)`'s
  `:=`, whose JavaScript half dereferences a bare `window` and therefore
  raises on every call under Node. The coroutine needs no globals and no `eval`,
  and it is what lets an operation be asynchronous.
  `bridge.pl` gains the job protocol behind all of it, the `o` tag for a live
  host value crossing by reference (so `G(x)` comes back as `x` itself), the
  space and registration verbs, and admission queues for a watch. Every
  predicate it calls is still published surface, which
  `tests/prolog/static_checks.pl` checks.
- The engine now declares what its platform can do, so a host asks instead of
  guessing. `library(thread)`, `library(time)` and `library(process)` are
  optional on a real build: SWI compiled to WebAssembly, which the browser
  playground and the Node binding run on, ships none of them. Loading them
  unconditionally failed there, SWI printed an `ERROR:` pair, the load carried
  on, and the only record of the loss was that text, which is why the Node
  binding parses the engine's boot transcript against a hand-kept table. The
  three loads are guarded now, on the rule `bindings/cmetta/decider.pl` and
  `bindings/python/decider.pl` already state for a seat: not present is not an
  error, half present is. Each guard records a capability fact, and
  `metta_platform(Capability, Status, Requires, Costs)` is the published
  `host_service` a host reads for the whole census, one row per capability with
  the platform library behind it and what its absence costs.
  Two families used to fail after boot, where no boot-time census could see
  them, and both refuse by name now with the cost stated: `(timeout N Expr)`
  and `(pragma! max-time N)` (deadlines, `library(time)`), and `(hyperpose ...)`
  plus the whole `lib_thread` family of `par-map`, `spawn`, `await`, channels,
  pools and blocking `take-atom` (concurrency, `library(thread)`). `git-import!`
  and `git-dependency` refuse the same way when `library(process)` is absent.
  A Prolog library says what it needs with `:- metta_requires(Capability)` at
  its top, read out of the source before the source runs, the way its exports
  already are, so a library that cannot work on this build never loads and the
  import refuses rather than the file half-loading; `lib/lib_thread.pl` carries
  one. This is npm's `engines` field and Python's `Requires-Python`, read from
  the metadata rather than discovered by running the package.
  Checked on a platform that genuinely lacks all three rather than a mocked
  one: `tests/prolog/reduced_platform.pl` mirrors SWI's library directories by
  symlink minus those four files and boots the engine against them in a child
  process, where `exists_source/1` is false for each and
  `call_with_time_limit/2` does not exist. On that platform the engine now
  loads without writing a single error line, still evaluates, and every
  affected form refuses naming the capability, the library and the cost
  [tested: tests/prolog/platform_capabilities.plt, 16 tests].
  Boot costs between 0.25% and 0.44% more instructions for it, and running a
  program costs nothing: `examples/basics/xor.metta` retires the same 9,289
  inferences either way, and boot inferences move from 688,190 to 690,780. The
  range on the boot figure is the measurement's own layout sensitivity rather
  than a range in the cost, which an inert padding block that neither side
  executes moves by about as much. A first version probed each library with
  `exists_source/1` before loading it, which resolves the same file name twice
  on a build that has it; that cost 6,271,103 instructions on its own and is
  gone, because `use_module/1` raises for exactly the missing spec and the
  recovery is the census row.

- A C binding, `bindings/cmetta`, so a C program can drive the engine: boot it,
  build and read MeTTa terms as C values, run programs, pull answers one at a
  time, and publish C functions the language calls. `cmetta.h` is the whole
  surface and `make test` runs its suite. It is the seam's third consumer and
  the first one that is IN the engine's process: where the Python seat crosses
  janus and the Node seat crosses WebAssembly, and both therefore encode every
  term into the tagged arrays `CODEC.md` describes, this one reads `term_t`
  directly and has no wire codec at all. That is also why the codec kit cannot
  gate it, and `bindings/python/tests/test_c_binding.py` gates it instead by
  requiring this seat and the Python host to answer the same programs with the
  same groups, multiplicity, text and metatypes.
  Ownership is carried by C's own type system rather than by documentation: a
  function taking `const cmetta_atom_t *` borrows and one taking a non-const
  pointer steals, so a nested build like
  `cmetta_expr(3, cmetta_sym("+"), cmetta_int(1), cmetta_int(2))` leaks nothing and
  a failed inner constructor releases the siblings that succeeded. Answers are
  stepped rather than drained, the shape `sqlite3_step()` gave C, so an endless
  MeTTa generator is ordinary from C. A published function names one of the five
  ranked effect classes, required rather than advisory, and reaches MeTTa
  through C's own casing convention, so `word_count` publishes `word-count`
  exactly as Python's `car_atom` reaches `car-atom`.
  Being in-process also lets this seat ask the engine directly which atoms are
  space references, rather than hardcoding a pair of names the way the shipped
  encoders did; the question both seats now ask is under Changed below.

- A scaling gate now holds each benchmark family to its declared complexity
  CLASS rather than to a constant, closing a hole every other pin in the tree
  shares: they are single numbers at single input sizes, so a cost that turns
  linear into quadratic stays invisible until it reaches the one pinned size.
  `sh check.sh scaling` measures each family across a ladder, fits `y = a*x^b`
  on the log of size against the log of inferences, and reports the exponent
  with R-squared beside google/benchmark's model selection. Four independent
  ways to fail keep the number honest: the exponent against the declared class,
  a separate looser guard comparing every size against its pinned row so a
  constant-factor loss inside the right class is still visible, a REFUSAL for
  any size that did not stay on one route, and an answer check run outside the
  measured region. Seeded with six families over the surfaces a class
  regression could hide in today, the write door, the reader, the join planner,
  the matcher, sequence variables and the MORK backend write path.
  It gates on inferences, which are deterministic: all eight families returned
  identical counts across three fresh processes at loadavg 3.40, again at 5.97,
  and again inside the full gate with the machine between 10 and 21, so the
  lane needs no quiet machine. `--selfcheck` asks the families about their own
  engine-level invariants, which is where the checks that need an engine live so
  the test file never boots one. `--paired` adds the retired
  instruction curve for a family whose work crosses into C or Rust, where an
  inference count is blind, and that lane is advisory.
- The scaling gate ships two planted negative controls permanently, and fails
  if either stops failing. One is genuinely quadratic while declared linear and
  must trip the exponent gate and only that gate; the other costs exactly three
  times its pinned row with its class untouched, and must trip the constant
  guard while passing the exponent gate, which is what proves the two gates are
  independent rather than one gate wearing two names. Their measured values are
  1.746 against a 1.25 bound, and 2.99x against a 1.10 bound at 0.999 exponent.
- The scaling gate refuses a run whose ledger was recorded under a different
  configuration, before it measures anything, and names the two remedies:
  restore the configuration, or re-pin with `--record`. The C reader alone is
  worth 10.58 to 10.86 times on the parse-forms family, [55248, 111250, 223254,
  452062] inferences on the Prolog reader against [5222, 10422, 20822, 41624] on
  the C one, and both routes hold the same class. Without the refusal the
  constant guard would fire at ten times its bound and name a parser regression
  where only the box differed. Running with `METTA_C_READER=off` on a tree whose
  ledger was pinned with `engine/reader.so` present now reports
  `CONFIGURATION DRIFT c_reader` and exits 1.
- Specializations now mint collision-free names from MeTTa-writable text and
  retain source-form equations for saving and digesting. Structured partial
  applications no longer leak Prolog syntax into stored symbols, and saved
  specialized programs reload with the same digest and behavior.
- The twins report now compares each example and Python twin with
  `Space.digest()` in separate processes. Digest refusals and absent results
  are findings rather than silently falling back to equation walks; unequal
  hashes carry a multiplicity-preserving canonical equation differential.
  The seven historically divergent tutorial pairs now state the equations
  they actually store or explicitly record that their content is identical.
- `PersistentFactSpace(..., rename={"old": "new"})` now materializes a
  one-open journal migration before replay. Every named old head must occur,
  the rewritten journal is atomically installed and validated, and later
  opens omit the map instead of retaining a standing alias. The persistence
  guide now states that the renamed atoms have different digests.
- The twin documentation now records the operational depth split between a
  recursive `.py` call and its compiled engine equation. A receipt lowers
  Python's recursion limit to 80, proves both paths answer `fib(10) == 55`,
  then observes `.py(100)` raise `RecursionError` while the engine answers the
  same definition under its LCO and reduction-fuel regime.
- Reified worlds now admit an evaluation only when its joined effect is
  covered. `space.covers(effect)` is an ordinary `(covers <space> <effect>)`
  catalog row; a world admits `pureStructural` without one and refuses
  anything stronger before it allocates scratch state or runs a single
  operation, naming the operation, its rank, the world's coverage and both
  remedies. The plan is the engine's own walk of the target and of the frozen
  image's compilation, so lowering a semantic head, hiding an operation behind
  a translator rule, or returning it as a masked result cannot smuggle an
  effect past the check, and a frozen image whose own equations compile
  effectfully is refused in `reify()` before any successor exists.
- `(did op args result)` receipts and compensating operations make the saga
  discipline ordinary data. `space.compensates(operation, recovery)` is a
  catalog row admitted only for `writesState`-or-stronger operations, and
  `with space.saga(receipts) as saga:` runs forward steps whose successful
  effectful answers commit one receipt atom each in the step's own
  transaction. A normal exit keeps the work and its queryable receipts; an
  exceptional exit resolves every declaration first, then compensates each
  receipt in reverse commit order, removing it only after its handler's own
  transaction commits, so a failed compensation keeps its receipt and is
  retried by `rollback()`. `AsyncMeTTa` carries all three faces as complete
  scopes on the owning worker.
- Python import layering is blocking again. The contracts exclude
  `TYPE_CHECKING`-only annotations, classify `_world` with the satellites,
  and document the four exact function-local boundary crossings. An adjacent
  planted-import selftest proves the production command rejects and names a
  new module-level core-to-satellite edge.
- `Space.lint()` now reports nine advisory Python-first design mixes without
  refusing execution: capital-data/lowercase-function role inversions,
  interpreter-equation shadows, registered operations inside compiled loops,
  module-level calls of defined functions, effectful operation calls during
  rule construction, operations staged into laws, `zip` and `reversed` over
  unordered `Answers`, and synchronous engine driving inside `async def`.
  Each source-observed finding carries its authority and position, operation
  findings carry the published five-rank effect, and both evidence and exact
  `# metta: ok(<kind>)` acknowledgements are queryable in `&metta` until the
  owning space is cleared.
- Semantic refusals now carry a structured Python-reference or named MeTTa-law
  ground. Comparison-term truthiness cites Python Language Reference section
  6.10 and names `S.le(1, V.x) & S.le(V.x, 10)` as the chained-comparison
  remedy; atom/plain ordering cites the rich-comparison data model.
  Every `CompileError` derives a ground from its refused construct, and the
  `refusal-grounds` gate plus its planted selftest keeps compiler, Python
  data-model, and segment-fragment fences grounded.
- Executable documentation now binds each gallery claim to adjacent `# ->`
  emitted-MeTTa and `# =>` shown-output comments by Python token span. The
  blocking `gallery` lane executes the named term, compares output as an
  alpha-equivalent multiset, and proves both checks reject planted drift.
  Emitted `@example` atoms now run through both their owning MeTTa definition
  and Python twin under the same multiplicity-preserving comparison. Six
  deterministic gallery programs cover multidirectional family relations
  under all five carriers, a validated journaled observed store, Linda
  coordination, immutable git-like worlds, symbolic tensor lowering to GEMM,
  and NetworkX expressed through the space and operation seams.
  NetworkX and NumPy join the `test` and `checks` extras so the gate runs all
  six, while the ecosystem and one-BLAS-GEMM programs skip where their package
  is absent, the way every other integration example does. The refreshed
  lockfile also drops the already-retired `orjson` extra and pre-3.12
  resolution branches.
- `@space.cache` now stores exact answer bags in generated SWI answer tries.
  Each proof contributes one to a mode-directed `sum`, so the trie keeps one
  copy of a distinct answer plus its occurrence count and replay expands that
  count back into the observable bag. `cache_info()` still reports call-key
  entries and answer occurrences, and stacking cache over `@space.op` still
  refuses before registration. A hidden generation argument now makes
  invalidation visible to already-live scheduler and pool engines whose SWI
  answer tables are private to their thread. On 2026-08-26, fib(25) measured
  2,548 cached inferences against 830,770 uncached: 4.49x less work than the
  11,433-inference Prolog-list memo, 1.57x the old 1,622-inference set table,
  and a restored uncached-to-cached ratio of 326x rather than 73x.
- The lazy default-engine tier now exports `@metta.op(effect=...)`, forwarding
  the complete receiver operation contract and its required five-rank effect
  metadata.
- Compiled definitions now accept `py(expr)` as an explicit inline host
  island. The expression executes at engine application time with current
  locals, while unmarked host calls refuse with a file/caret span and name
  both `@metta.op` and `py(...)` remedies. `lint()` reports a
  `host-island-in-loop` warning for repeated crossings.
- `Space.answers(..., theory=...)` now evaluates one ask against a complete
  atom-valued theory in an isolated scratch space, leaving the receiver
  unchanged. `Space.answers(..., interpreter=...)` evaluates the corresponding
  `(interpreter target %Undefined% receiver)` application for that ask. The
  two selectors are mutually exclusive, a choice recorded here because both
  otherwise claim the evaluation relation for the same cursor.

- Call-site keywords on `Defined` values and bound `space.fn` functions now
  resolve to the known definition or operation signature and emit the
  positional MeTTa application. Bare symbols such as `S.head(x=value)` refuse
  with an explicit positional remedy instead of silently appending a generic
  `(Kwargs ...)` term; grounded Python-call heads retain that transport form.

- Compiled Python bodies now lower `assert condition[, reason]` to the
  language's `(Error condition reason)` algebra, preserving generator
  continuations. `del space[pattern]` snapshots and removes every match;
  `space -= atom` on a `Space`-typed parameter removes one occurrence. Missing
  removals remain Error answers.

- `Space.reacts(pattern, operation, priority=None)` and its async mirror now
  expose the settled declaration spelling for `(on ...)`; `reaction(...)`
  remains as a compatibility alias.

- `metta.testing.from_pattern(pattern)` now generates ground pattern
  instantiations for property tests, preserving repeated named-variable
  identity and drawing anonymous occurrences independently.

- Reader-token registration and removal now accept compiled text
  `re.Pattern` objects, translating `IGNORECASE`, `MULTILINE`, `DOTALL`, and
  `VERBOSE` flags to the engine PCRE and refusing flags with no exact
  translation. Anonymous-space representations now include the external
  `file:line` that created the handle; named-space representations stay
  compact, and async creation retains the submitting coroutine's location.

- `metta.catalog` now names the queryable `&metta` reflection space, and
  `fresh()` now mints hygienic variables for library-authored patterns. These
  deliberate root additions raise the narrow public export count from 100 to
  102.

- `atom.cast(type_)` now delegates to `space.cast(atom, type_)` in the ambient
  space, preserving space-relative type admission with the concise atom door.

- `spawn` now runs each computation as a suspended SWI engine and multiplexes
  those engines over a bounded normal carrier pool. Space writes wake parked
  engines without parking a carrier. Future awaits, empty channel receives and
  full channel sends suspend their engines too. `oracleIO` operations use Go's
  blocking-syscall shape: the engine detaches onto a transient offload thread,
  leaving every bounded carrier free until the foreign call returns.
  Coroutine functions registered with `@space.op(effect=...)` now answer a
  typed `FutureSpace`; transaction commit publishes their launch before the
  coroutine starts, and landing is a later event. Rollback discards an
  unstarted launch. `@space.define` names this future-space route and
  `aio.AsyncMeTTa.call` as its two async remedies. Context variables are
  copied at every coordination and worker spawn door, including OS threads.
  The bounded M:N path also removes the dedicated-thread launch cost for tiny
  jobs: a min-of-five fresh-process probe of 200 `(+ 1 1)` spawns took 4.617 ms
  versus 6.737 ms on the prior dedicated-thread face, 0.69 times as long. In
  exchange, 128 parked waits held 9 OS threads instead of 131. [measured: min
  of five fresh SWI processes;
  command=`for iteration in 1 2 3 4 5; do swipl -q -f tests/prolog/async_scheduler_bench.pl -g bench -t halt 2>/dev/null | command grep '^cheap_ms='; done` in the candidate and base checkouts;
  fixture=candidate checkout against 6aa5a6785feaf39a7a2d4ab4a26817bc063aea92, 200 cheap spawns and 128 parked waits;
  commit=39092863ae34184a9f955f185ff57c1ff177ec40]

- `bindings/python/bench.py --memory-scale` measures memory and scaling in
  spawned fresh processes. It keeps min-of-three raw samples and noise bands,
  fits constant through quadratic and capped-linear complexity families over
  geometric sizes, and separates exact SWI structural bytes from Python
  allocations and Linux process memory. Controlled `instructions:u` samples
  cover primitive-heavy projection width. Exact lanes also gate atom, grounded
  object, MORK space, table, module-pool, and bounded wire-cache reclamation;
  page-based RSS, PSS, and private bytes remain report-only. The streaming
  answer curve uses numeric payloads so its constant cursor-memory result is
  not confounded by the separately measured wire-name cache.

- Python operations can be relations without a separate inverse: an encoded
  generator's exact tuple yields are positional candidate bindings and exact
  dict yields are sparse parameter-name bindings. The engine filters ground
  arguments and binds free ones through the same implementation while
  preserving duplicate answers. Effects fire exactly once per yielded
  candidate searched, including candidates rejected by bound arguments;
  `inverse=` remains available for a genuinely distinct backward
  implementation. Package `unify` is now symmetric at two
  arguments and exposes the engine's four-argument conditional both at
  expression position and inside compiled bodies, closing the P14.36
  directionality divergence.
- Algebra annotations now travel through the query doors themselves.
  `Space.match(..., under=carrier)` and
  `Space.answers(call, under=carrier)` accept the shipped `counting`,
  `tropical`, `prov`, `ranked`, and `prob` carrier objects or an arbitrary
  declared algebra; `with metta.under(carrier)` supplies a task-local default.
  Counting is an engine aggregate that preserves duplicate derivations without
  materializing answer rows. Ordered carriers sort before an `Answers` slice,
  making `match(..., under=ranked)[:k]` top-k and tropical order
  cheapest-first. Annotated
  answers retain their derivation for `.why()` and `.under(other)` without a
  re-query. The real `metta.algebra` module is now also the constructor, while
  the former `Space.evaluate_algebra` door is retired. `Space.sample(q, k=10,
  seed=7)` replaces `sample_rates` with `random.choices` vocabulary: it returns
  a list, samples with replacement, reads implicit `(rate n)` tags, and uses an
  isolated seeded generator. Event folds now accept `into=State` for a running
  gauge or `under=algebra` with no step body; the State store is process-shared,
  individual accesses are thread-safe, compound read-modify-write is not
  atomic, and cells remain outside events, history, and transactions.
- Operation effects are a required five-rank contract:
  `pureStructural < readOnlyLookup < nondeterministicReadOnly < writesState <
  oracleIO`. `EffectClass` compares in that order and composes a plan by taking
  its strongest member; registered operations and compiled definitions expose
  the resulting canonical `(effect name class)` row in `&metta`. Registration
  without effect metadata now refuses with all five remedies. New code supplies
  it through `effect=`; the retired declaration spellings
  remain accepted as input aliases and canonicalize conservatively:
  `immutable` to `pureStructural`, `stable` to `readOnlyLookup`, and `volatile`
  to `oracleIO`.
- Transactional, atomic, speculative, and reified-world writes now publish
  watcher, fold, and journal events only after commit, in write order; rollback
  and discard publish nothing. The Python-first surface adds
  `metta.speculate()`, `space.reify()`, `world.eval(...)`, and
  `space.commit(world)`. Journaled providers stage their writes with the same
  law. Live `State` cells are fenced from speculative and persistent writes,
  while compiled `cell.value` reads and writes lower to the engine's state
  operations.
- `lib_strategy` ships the Stratego-like rewriting basis as ordinary queryable
  terms: `id`, `fail`, `seq`, left-biased `choice`, `try`, `repeat`, `all`,
  `one`, strict `topdown` and `bottomup`, `innermost`, the `stratego-all` and
  `stratego-one` spellings, and the TP/TU typed traversal schemes.
  `strategy-apply` is a translator rule whose expansion remains an atom and
  executes through the engine's rewrite machinery rather than a host callback.
  The lazy `metta.strategies` satellite builds the same plans, spelling the
  Python keyword as `try_`; import the basis with `m += lib.strategy`. The
  executable phrasebook now covers 147 of 181 callable LeaTTa operations, and
  `examples/libraries/strategy.metta` holds 35 assertions over the laws,
  traversal order, failure, reification, and typed schemes. The translator
  metatheory collector now treats `quote`, `noeval`, and `Error` payloads as
  data, so runtime terms emitted by a translator rule do not become false
  compile-time recursion edges.

- Benchmark baselines are two-sided and configuration-stamped. A counter,
  slope, or instruction reading that falls beyond the allowance now fails as
  an unpinned improvement instead of passing silently, because a stale-high
  pin masks real regressions up to its own margin: `file-load` sat pinned at
  8,704,891 inferences while the tree measured 722,264, twelve-fold masking
  headroom the one-sided check never surfaced. Every re-pin in
  `benchmarks/baseline.json` and `benchmarks/extension-baseline.json` records
  its measured mechanism beside the pin (the C reader's artifact gate, the
  1d28398f capability flip, the typed-dispatch train, the identity wire's
  codec saving, and the daeb3b5a dispatch-ownership door are this round's).
  Both documents also carry a `counter_configuration` stamp (`c_reader`,
  `c_extension`): comparisons refuse to run in a configuration other than the
  one the pins were measured in, since artifact presence alone moves pins
  with zero code change. The instruction checker verifies the stamp without
  rewriting it, `worktree.sh` builds `engine/reader.so` from the worktree's
  own source so an isolated tree measures the shipping configuration, and
  the extension-cost gate fails on any pinned row nothing measured, pruning
  such rows aloud on update - which restored the C foreign row (silently
  absent since the tree partition moved the harness a directory deeper and
  its artifact path stopped resolving) and retired the renamed
  `raw-true` row. `EXTENDING.md`'s cost tables are regenerated from the
  gated harness.

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
  never shipped; the Node/WebAssembly host mounts sources only, and the
  typed development build (`tests/prolog/dev_typed.pl`) sets SWI's
  `source` flag so its expansion always sees the `.pl`.
- Add the library import door: `m += lib.he` performs
  `!(import! <m> (library lib_he))` with the receiver as the target space.
  `metta.lib` is the catalog-generated namespace whose attribute map is the
  `lib_` family prefix with underscores kept; `lib["exact_name"]` reaches a
  library outside the family or one whose suffix Python cannot say
  (`lib_import` strips to the keyword `import`), `lib.x.part` builds the
  two-argument `(library x part)` form, and `lib(S["path/to/module"])` is
  the exact-module-form escape: a path import is named by its ATOM, which
  the engine resolves by its own rules rather than against the host's
  working directory (`str` and `os.PathLike` stay accepted one rung
  down). A handle refuses term positions, mixed adds, and batch
  scopes loudly; a missing library surfaces the engine's own existence
  error.
- The conformance kit is universal: `check-space-provider`
  (lib/lib_conformance.pl) now also holds a provider to the pattern-family
  match law (every stored atom must be answered for itself, for each
  position opened to a fresh variable, and for its repeated-variable
  folds, asked through the engine's own match router), the declared
  source discipline (a `repeated` provider's two enumerations must
  agree, a `linear` one is not asked twice), and an add-enumerate-remove
  canary round trip through the provider's own write hooks. The same
  checker serves every substrate: `metta.testing.check_space_provider`
  handed an engine `Space` handle dispatches to it through the seam, so
  a provider whose clauses live in Prolog and whose store lives in C is
  held to the same contract as a Python object.
- Extensions have a readying moment: `:- metta_extension(name,
  [spaces(['&s', ...])])` validates each named space when its file
  finishes loading, refusing loudly (with the remedy in the message)
  when the space was never registered, declares no capability, or
  declares a capability whose seam hook has no clauses behind it.
  `check(true)` additionally runs the full conformance kit at that
  moment. The shipped cstore example and the demo provider fixture
  declare their spaces.
- Keyword arguments have a Python-authored spelling: `S.f(x, stop=8)`
  and a grounded head's call accept `**kwargs` and append the seam's
  `(Kwargs (name value) ...)` form, one mechanism at the builder for
  every head, so a numpy-style call like `np_arange(start=2, stop=8)`
  is writable as Python. Keyword parameter names are exact.
- `Space.metta` answers the owning evaluation context, so a handle held
  alone reaches the ruled creation door as `m.metta.space(name)` and
  the context's other doors without the process default being assumed.
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
  through `metta_py_limited/6`.
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
  `metta_py_limited/6` threads the same bound with a negative-value no-bound
  sentinel; `metta_py_limited/5` is unchanged.
- `metta_py_function_generation/1` exposes the process-global `fun/1`
  catalogue generation for cheap host cache invalidation. It reads SWI's own
  `last_modified_generation`, so definitions bump it, evaluation and data
  writes do not, and translator-rule changes are neutral because they do not
  affect `metta_py_builtins/1`.
- `@metta.rules` turns a generator whose parameters are rule-local variables
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
  protocols and standard library with no `metta` name at all, 16 wear one and
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
  is a hole for a backwards call to fill, and `metta.fn` is an inert
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
  The Node binding now decodes that tag into an immutable JavaScript
  `SpaceHandle` whose only state is the engine name, re-encodes it as `p`,
  and runs the `space-handle` corpus case on read, render, round-trip, and
  transport.
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


- **The matcher is upstream PeTTa's, and its whole cycle discipline is one
  test per answer.** Matching binds raw, with no occurs check, so first
  argument indexing dispatches and a repeated pattern variable may bind to a
  term that contains it: a rational tree is a legal binding. The single cycle
  test sits on the ANSWER template. Against a stored `(rt (f $x) $x)`, the
  pattern `(rt $y $y)` with an out template of `hit` answers `hit`; the same
  pattern used as its own template answers nothing, because that answer is
  the cyclic one; and with an acyclic `(rt ok ok)` stored beside it the `hit`
  template answers twice. That is upstream's own measured law, and it
  withdraws the previous one, under which a rational-tree instantiation was
  never an answer whatever the template.

  What went with it is apparatus rather than protection. The per-candidate
  occurs check, the entry scan that had replaced it (the cycle-guard
  linearity gate computed once per call) and that scan's C twin all moved the
  same growing-term walk between spellings without removing it, and the entry
  scan added a per-call classification the walk never needed. What remains is
  upstream's `\+ cyclic_term/1` on the answer, spelled `acyclic_term/1`
  because it is the same walk at half the inference price. One refinement
  past upstream's spelling: upstream re-tests the template after every
  conjunct step, an artifact of its recursive clause, so the test here sits
  only at answer sites and a skew join pays nothing per step.

  The aligned path is the cheaper one here too. The Peano parity example runs
  47.34G instructions before and 37.19G after, -21.4%, across the regression
  fix and the adoption together; the benchmark suite's match case falls by
  11,400 inferences and match-skew by 300.

- **`let` and `unify` bind raw under the same one law.** Upstream's `let`
  emits a plain `=`, measured: `!(let $x (f $x) worked)` answers `[worked]`
  there and the rational tree itself flows out when the body mentions it, so
  the occurs checks in the typed and untyped `let` emissions, the duals'
  `let` generator and `unify`'s variable case all left with the arbiter that
  required them. A self-referential binding now answers its rational tree,
  which the translator and spaces suites pin end to end. Every counter lane
  shed the shared constants: `py-method-call` -80,022 inferences (-3.5%),
  `space-name` -240,008 (-5.8%), `direct-join` -14.2%, and the automatic
  tabling separation at n=20 widened to 1,528x.

- **A rational tree is a legal value with two honest exits.** Display
  answers SWI's factorized cycle form, the shape the upstream toplevel
  presents, because every walker below would follow the cycle forever;
  serialization (`swrite/2`) refuses loudly, since no finite S-expression
  reads back as a rational tree; and the Python wire refuses the ROW loudly
  with the remedy named, where it previously dropped the row in silence and
  `len` disagreed with what a caller could read (the encoder measured 6.7
  million frames to the stack limit before the guard).

- **Parity with upstream PeTTa, measured: the corpus runs in 36.7% of
  upstream's instructions at the median.** Over 149 measured examples the
  median instruction ratio is 0.367, with individual files from 0.05x. The
  hardest case the campaign started with, `06-peano.metta`, is now 1.006x
  where it was 1.29x, so its waiver is gone rather than re-worded, and
  seventeen others followed it out of the table: a waiver that describes a
  cost the engine no longer pays is a false claim, not documentation. The
  fifteen that remain each keep a root cause and now cite the figures this
  tree measures. One example is excluded rather than waived, and says why:
  its last block writes from four threads through `hyperpose`, so its
  inference count moves with the interleaving (0.004% over four runs) while
  its answer count does not.

- **A resource may not die while a reference handed out of it lives.** The
  abandonment backstop watched the context object, so the chained spelling
  `MeTTa().self` left the context unreferenced and released its home into
  the free-name pool while the handle still named it; the next mint drew
  that name back and refused, naming a space that would inherit from
  itself. The backstop watches the home handle instead, which is what a
  caller keeps. The same defect cost real work: a released home was rebuilt
  on the next write, which is why the identity twin's budget had been
  re-pinned upward by 2,508 inferences for an execution module built twice.

- **A dropped space reclaims its atoms.** The store now clears in its own
  engine query ahead of the release, under the same mute the release uses,
  because a query cannot reclaim the clauses it erased while it still runs:
  clearing inside the release left 20,008 atoms of a 10,000-atom workload in
  the table where 6 belong, in five of six fresh processes. Measured against
  the pre-change tree, which reclaimed in three of three, and now constant
  across every size the memory-scale lane walks.

- **Construction refuses before it acquires, and abandonment has a
  backstop.** `space()` validates its whole request before minting, so a
  refusal costs nothing where it used to leak an anonymous space per
  failure; the acquisitions that follow run under one unwind that closes an
  owned journal and drops only a fresh mint, never a named open, whose
  destruction could be data loss; and `copy()` enumerates its source before
  minting the clone. A collected `MeTTa()` now releases its world and an
  abandoned `watch()` iterator cancels its subscription, `weakref.finalize`
  backstops that detach when the `close()` contract runs. On a borrowed
  home, explicit `verbose=`/`metta_path=` route through the runtime door
  instead of being silently ignored, so a conflicting engine path refuses
  with the one-engine remedy.

- **Saga durability holds when the write about the write fails.** A failed
  receipt persist retains the obligation unjournalled and retryable instead
  of raising it away, and recovery preflights journalled receipts before
  letting unjournalled obligations compensate without one, so an external
  effect can no longer outlive both its record and its reversal. Foreign
  participants now commit one at a time with per-participant outcomes: a
  refusal rolls back every participant it never reached, a commit that
  merely failed is a named refusal instead of an unbound result, and a step
  whose non-journal participant lost its writes refuses by name as the
  mixed outcome it is, naming the transactional-outbox remedy, rather than
  compensating an effect that never committed. Journal attachment takes an
  exclusive flock on a sidecar lock spanning tail repair, migration and the
  provider's life, because SWI's own record lock binds the inode and cannot
  see a pathname being replaced under another process.

- **The manifest keeps the guard, the truth, and every close.** Manifest
  attachment routes through the same same-process refusal the direct door
  uses instead of bypassing it into a transport-timeout deadlock; a boot
  form whose effect performed but whose `(boot ...)` record raised says
  exactly that, instead of claiming the form did not perform; and cleanup
  attempts every server close, aggregating failures, rather than stopping
  at the first. `queue_max` refuses non-finite values, NaN having defeated
  the bound's comparison and queued without limit.

- **`temp-path!` joins lib_file.** One call answers a unique fresh path in
  the system temporary directory, created exclusively so concurrent
  runners cannot mint the same name; the text-library example and its
  Python twin use it in place of the fixed `/tmp` names that could collide
  across checkouts.

- **A context's world is one unit: program mints join it, and close takes
  it down.** A space the program mints with `new-space` inside a `MeTTa()`
  context now declares the context's home as its equation home, so `super`
  and `evalc` find definitions the program wrote at its own top level; the
  four example-parity divergences this had caused (`04-super`, `05-evalc`,
  `02-memo_aggregate`, `06-spaces_removeallatoms`) all closed with it.
  `close()` releases every space minted inside the context, the handle's
  python side swept first so subscriptions cannot follow a pooled name into
  another life, while a space the program declared with `(inherits ...)`
  still refuses by name. The super-user recompilation the removal funnel
  fires is muted during a release, because a dying world's own users die
  with it and cross-world users cannot exist.

- **The semantics arbiter is upstream PeTTa, vendored and gated per file.**
  `tests/conformance/petta/` holds upstream's example corpus beside the exact
  bytes upstream printed for each entry, captured from commit `ae66fa8e`, and
  `check.sh`'s conformance lane replays every entry against this engine. The
  measured divergences the alignment closed, each probed on both engines
  before it moved:

  - `==` and `!=` are pure term equality declared `(-> $a $b Bool)`:
    `(== 1 1.0)` is `False`, `(== 1 "s")` is `False` where both refused, and
    a written `(Error ..)` atom compares as the term it is. An error an
    OPERAND computed still surfaces as the answer, carried by the call's
    argument guard rather than by the comparison.
  - A function result does not re-enter evaluation, so a held operand a body
    passes through stays as written all the way out, exactly as upstream
    compiles the equation.
  - `chain` and `let` bind the VALUE the operand produced; `eval` answers
    the operand it evaluated rather than the `(eval ...)` call.
  - The evaluation budget is opt-in: with no `max-stack-depth` pragma the
    engine compiles no charge at all and recursion runs to completion, as
    upstream does; naming a budget recompiles the affected functions with
    the charge in place, so the pragma still binds from its first bounded
    call.
  - Any symbol names a space the moment it is written to; `is-space` keeps
    the `&` test, which is upstream's own split.
  - Too many arguments raise `domain_error(function_input_arities(F, Known),
    Asked)`, naming the arities the function has beside the one asked for;
    a head that names nothing stays as written.
  - `pow-math` keeps its operands' numeric kinds (`(pow-math 2 3)` is `8`),
    `min-atom`/`max-atom` answer `()` for a non-expression and nothing for
    an empty one, every numeric operation refuses a wrong operand by name,
    and an all-integer zero division answers the contained `DivisionByZero`.
  - A `test` whose expression produced no answer compares as `()`; Curry's
    functional pattern compiles a call in head position to a goal run
    backwards; in-place `(: $x T)` head annotations read as ordinary
    structure; relative imports resolve against the working directory first;
    a host loader called from MeTTa loads into the process tier.
  - A function whose equations all miss answers nothing (`NoMatchFail` is
    the dispatch default); the previous behaviour is one
    `(dispatch-policy <f> NoMatchEnum NoMatchOriginal)` away.

- **One attach door, and `space()` declares its whole surface.**
  `metta.remote.attach` is gone: a remote space is `RemoteSpace` over a
  transport, and `metta.attach(name, backing)` registers it like any other
  backing (`connect()` builds the transport when it needs a token, headers,
  an ssl context or a timeout; a bare URL keeps working through the same
  derivation). `space()`'s options are real keyword parameters now --
  `inherits`, `restricted`, `grants`, `journal`, `schema`, `sync` -- so the
  type checker and completion see the door; the remote knobs left it, and a
  bare transport callable is refused with the composition named. `MeTTa()`
  is an isolated context that owns the home it mints (`close()`, `with`,
  equality by runtime-and-home), sharing is spelled (`Space()`,
  `metta.engine()`), a context's spaces resolve equations through its home
  by the narrow equation-home relation, and verbosity applies only when a
  caller says something.

- **The aligned paths are also the cheaper ones.** The guards a program
  never uses are not compiled: the fuel charge, the masked-result chain and
  error tests around the total-boolean operations, the match door's
  per-conjunct cycle walks (one test per answer replaces them; on the
  Peano example those walks alone were 12.7% of the run), and the
  translator-rule orientation gate, whose evaluation-boundary and reduce
  doors hold a body that never asks the rule table while no bidirectional
  rule is registered and swap the gated body in when one is. Run-time `eval`
  translation is cached on a literal-abstracted skeleton, the
  branch-return analysis keeps its statistics as variable attributes with a
  C twin behind the reader's artifact pattern, and dispatch under the
  default policy goes straight to Prolog's own clause selection.

- **`remove-atom` drains every unifying occurrence and answers `True` either
  way, which is upstream's law.** It took ONE occurrence and answered
  `(Error (remove-atom <space> <atom>) "remove-atom: atom is not in the
  space")` for an atom the space did not hold. Both readings came from an
  arbiter this engine no longer follows; upstream's is `retractall/1` under a
  comment reading "Remove all same atoms", and it answers `true` whether or
  not anything went. A different ANSWER to the same call is the one thing the
  superset rule does not allow, so the door follows upstream.

  The finer grain did not go anywhere, and each Python door now takes the
  behaviour its own Python spelling implies. `space.remove(atom)` is
  `list.remove`'s grain: one unifying occurrence, and it returns whether it
  found one, so absence is still reportable. `space -= atom` is Python's
  in-place difference, which is total, so it drains and says nothing about
  absence. `del space[pattern]` drains and raises `KeyError` when nothing
  unified, as Python's `del` does. Provider authors are unaffected:
  `seam:foreign_remove/3` is still "remove one", and the door above it reads
  the matching atoms and then asks the provider once for each.

  One consequence is worth knowing if you write hooks: the removal hook now
  fires once per occurrence and carries the ATOM THAT LEFT rather than the
  pattern the caller wrote, so a handler no longer has to re-read the space to
  learn which occurrence went.

- **The README is rewritten to declare rather than explain, and to run.** It
  goes representation first (the four atom kinds, in MeTTa and then in Python),
  through spaces and queries and `@define`, to what the engine does that a
  library cannot: a function written forwards run backwards through `solve`,
  many answers as the normal case, and equations as atoms a program can add and
  query at run time. Then the three axes, async, parallelism, HTTP, providers,
  and the TypeScript and C seats showing the same two definition doors.
  Every Python block executes, and each now runs in a namespace of its OWN, so
  a reader can copy any one of them; they used to share one namespace in order,
  which meant a block could depend on one further up the page without saying
  so. The blocks build terms rather than passing MeTTa source strings, because
  `m.run` is the door for whole programs as text and a built term is knowledge
  already, which is the library's own rule about strings applied to its own
  front page.

- **`Space.writes` now declares an OPERATION's effect, and the space's write
  contract is `Space.atomicity`.** The two were one name for two concepts on
  one object: `(writes <ctx> transactional|atomic-single|best-effort)` is a
  claim about a space's write door, while the effect decorator classifies one
  operation. mypyc found it, because the decorator's callable argument and the
  contract's `Atomicity` cannot be the same parameter. The stored atom keeps
  its `writes` head; the method is named for what it declares.

- **The C seat is CMeTTa, because CeTTa is a different thing.** `extensions/
  cetta/` becomes `extensions/cmetta/`, with `cmetta.c`, `cmetta.h`,
  `libcmetta.so` and every identifier inside it (`cmetta_dispatch`,
  `pl_cmetta_apply`, `CMETTA_*`). The two names were one letter apart and named
  two different projects: **CMeTTa** is this repository's own C seat, a C
  program that drives the engine through SWI's foreign interface, sibling to
  the Python and Node seats. **CeTTa** is the vendored upstream C substrate, a
  fork of another author's runtime kept in a sibling checkout outside this
  repository, which this repository does not contain and only compares itself
  against.
  That second one is why the rename is careful rather than mechanical.
  `tests/conformance/cetta.py`, `cetta_corpus.py`, `cetta_fences.txt` and
  `cetta_shared_fragment.txt` all keep their names, because they replay the
  conformance corpus through THE FORK's C core and resolve it through
  `CETTA_PATH`; so do the two Python tests that drive them. A first pass
  renamed those too and broke the lane, which is the tell that a rename over a
  name with two meanings has to read each use rather than match a pattern. The
  engine's citations of the seat's constraint ledger move with it: `CeTTa C2`
  and `CeTTa C12` are now `CMeTTa C2` and `CMeTTa C12`, and the ledger itself
  is `ai-cmetta-c-constraints.md`.
  History is not rewritten: entries above this one keep the spelling they
  shipped with.

- **The Python twin corpus is called what it is and sits where it belongs:
  `extensions/python/examples/language-feature-examples/`.** 219 files that
  answer the whole shipped MeTTa corpus in Python lived under
  `extensions/python/tests/twins/`, where the word `twins` said what they are
  RELATIVE to something else and `tests/` said they were test modules. Neither
  is true from a reader's side: what they are is the language's features, shown
  as examples, in Python, which is why a reader goes to them at all. They move
  beside the topical examples and the folder says so. The path transform that
  addresses a file by its example's own path is unchanged, mirroring
  `examples/` directory for directory, so `twin_coverage.py` finds all 219 with
  no orphans.
  Two consumers changed shape rather than just their paths. The
  examples runner globs `*.py` RECURSIVELY, so it would have run each of the
  219 as a standalone program: each defines `twin(m)` and verifies nothing when
  executed alone, so the runner names and skips the folder, and the README
  beside it says why. And `ruff` covered the corpus only because `tests/**` was
  one of its three arguments, so the lane now names the corpus directly and
  `pyproject.toml` carries the per-file ignores that used to reach it through
  `tests/**` -- a language-feature example MIRRORS its MeTTa original, and
  `SIM210` on `05-if4.py` is a request to stop mirroring
  `(if (== 42 42) True False)`. The lane is not widened to all of `examples/`,
  which would newly fail on 184 findings in the topical examples that predate
  this and belong to their own burn-down.
  `extensions/node/example/` becomes `extensions/node/examples/` in the same
  breath, so every seat spells the directory the same way, and
  `extensions/README.md` states the convention: a seat that mirrors the corpus
  puts it in `examples/language-feature-examples/`. The Node and C seats answer
  the shipped corpus from the Python side today and ship no folder of their own.

- **`run()` crosses on the predicate door, and stops re-parsing its own goal.**
  `_direct_run` built the text `metta_py_run(Src, Space, Groups)` and called
  `Runtime.must`, so janus re-parsed that goal on every directive, while
  `metta_py_run/3` was already shaped for janus's functional convention --
  ground inputs then one output -- which is the door `evaluate()` beside it has
  used since `1ec64474`. `space.run("!(+ 1 2)")` falls from 28.47 to 25.29
  microseconds of process CPU, -11.2%, and from 436.00 to 431.00 inferences a
  directive, exactly -5.00 and exactly reproducible; the `run-source` wall
  figure falls 35.85 to 25.77, -28.1%. The door was chosen by census rather
  than by reading: of 950 engine calls in ordinary work (200 adds, 200 evals,
  100 matches, 50 runs), 900 were already on the predicate door and all 50
  stragglers were `run()`. Priced on its own the door is 4.24x, 1.162 against
  0.274 microseconds on a trivial call, and the goal-string door's cost tracks
  its TEXT LENGTH at 5.75 ns a character over identical work. Eight baselines
  and the four automatic-tabling pins move at that one rate, each recording it.

- **The engine owns its own gate lanes, in `engine/check.sh`, and the root gate
  now carries only lanes whose subject is the repository.** Twenty-nine move,
  beside the `engine-bench` lane the component already had: the example corpus
  in both its lanes (`shell`, `examples`), the three oracles that prove its
  runner detects a failure, reports it, and does not have a pass destroyed
  under it (`shell-oracle`, `shell-failure`, `encoding`), the specializer
  differential, the three shell suites only `ci.yml` used to run
  (`git-dependency`, `git-import`, `loader-threads`), the Prolog analyses
  (`prolog`, `ciao-grade`, `prolog-static`, `prolog-reach` and its selftest,
  `prolog-metatheory`, the three `translator-confluence` lanes, both
  `dev-typed` lanes, both `engine-integrity` lanes), the corpus law
  (`cumulative-syntax` and its selftest), `no-autoload`, `lib-surface`,
  `layering`, `prolog-determinism` and `plunit`. `extensions/python`, `extensions/node` and `extensions/cmetta`
  already owned theirs, SOURCED rather than executed by the root driver's
  discovery loop, which is what keeps one `run`, one summary table and one exit
  status.

  The seventeen shell functions those lanes call move with them, from
  `run_example_corpus` to `check_plunit`, and no function is reached by both a
  moved lane and a lane that stays. `run`, `in_py`, `$PY`, `$PYDIR` and `$HERE`
  stay with the root driver, which is what sourcing makes available; `run` is
  called from all four component scripts and `in_py` from the Python one.
  Nothing a lane does changes: what the root keeps and the four regions the
  component gains reassemble the previous `check.sh` line for line, the 86 lane
  names and their tiers are identical, and `sh check.sh <lane>` still selects
  any of them, which is the door `.github/workflows/checks.yml` uses.

  What stays at the root is what the root is the subject of: the conformance
  arbiters (`leatta`, `cmetta`, `cmetta-corpus`), the generated-documentation
  lanes (`reference`, `libdoc`, `codec-doc`, `vocab-sync`, `llms`, `snippets`,
  `docs`), the readers that model the gate's own shape (`evidence`,
  `spec-status` and their selftests), `policy-inventory`, `refusal-grounds`,
  `codespell`, `jscpd`, `ruff-drivers`, `build` and `worktree`.

  `tests/checks/evidence_runners.py`'s plunit collector names the component
  now, the same field the pytest collector needed when the Python lanes moved.
  Left on the root it reports the anchor as gone and the suites drop out of the
  executed model carrying the files only they load: 601 executed files with the
  field naming the component, 537 with it stale, the difference being 47 of the
  49 `.plt` suites, the eight shipped libraries their bodies consult and nine
  `tests/prolog` providers. Both selftest fixtures build an `engine/check.sh` of
  their own now, so the split is the shape they prove against
  [tested: sh check.sh evidence evidence-selftest spec-status-selftest].

- **The Python component owns its own gate lanes, in
  `extensions/python/check.sh`.** The root `check.sh` carried 80 lanes and the
  largest block of them had a subject that was not the root: `pytest`,
  `gallery`, `benchmarks`, `instructions`, `scaling`, the two memory-scale
  lanes, `packaged`, `parity`, `twins`, `phrasebook`, `extcost`, `determinism`
  and the whole static-analysis tier, twenty-eight in all. `extensions/node`
  and `extensions/cmetta` already owned theirs, SOURCED rather than executed by
  the root driver's discovery loop, which is what keeps one `run`, one summary
  table and one exit status; the Python component owned none, so `metta list`
  read `-` under CHECK for the component carrying the most lanes in the gate.
  The three shell functions those lanes call move with them,
  `memory_scale_report`, `memory_scale_gate` and `check_determinism_coverage`,
  while `run`, `in_py`, `$PY`, `$PYDIR`, `$HERE` and the two memory-scale
  temporaries stay with the root driver, whose EXIT trap is what removes them.
  Nothing a lane does changes: the two files reassemble the previous
  `check.sh` line for line, the 80 names and their tiers are identical, and
  `sh check.sh <lane>` still selects any of them, which is the door
  `.github/workflows/checks.yml` uses.

- **The repository is MeTTa Kernel, and no name it owns is spelled `petta` any
  more.** The Python module rename left the spelling behind in places that were
  never swept: the project URLs and CITATION metadata, the CI container image,
  the site's project-hosting base path, `metta_c_set_silent/1` in the engine's
  own comment and in two tests, `CODEC.md`'s `metta_c_space_operand/1`, and a
  test beacon string. `&petta` went with them, and that one was not a rename but
  a correction: the engine's boot spaces measure `['&metta', '&self']`, so the
  public `Space.space_names` docstring, the guide page reproducing it and the
  engine-free `shim.plt` fixture had all been stating a space that does not
  exist. What is deliberately NOT renamed is every name belonging to something
  else: the upstream repositories this one forked from, which the lineage
  section exists to record, `../PeTTa-base` and the prose comparing against
  upstream, and the sibling packages `pettagrapher`, `pettaprove` and
  `jupyter-petta-kernel`.

- **The Node and C seats spell what they own `metta`.** The Python rename
  stopped at its own module: `metta` shipped with `metta_py_*` transport
  predicates while the other two seats still said `petta`, so one seam carried
  two spellings for one idea and the odd one out was whichever seat you had
  open. `PettaError` is `MettaError`, 92 occurrences, joining the Python
  seat's own `MettaError` with no alias left behind. The transport families
  follow: 61 `metta_node_*` names over 304 occurrences, and 35 `metta_c_*`
  names over 102. The npm package is `metta-node`, its two symbol
  descriptions are `metta.atom` and `metta.goal`, the checkout mounts at
  `/metta` inside the WebAssembly filesystem, and `wire.ts` names `&metta`,
  which is the space the engine has answered since the metadata space moved.

  Each seat's two halves moved in one step because no compiler can see between
  them. `src/engine.ts` names eight bridge predicates as query strings and
  `cmetta.c` names twenty through `PL_predicate`, `call_bridge` and
  `space_call`, so a literal left behind is an existence error at run time
  rather than a build failure. `CODEC.md` cited one of the twenty and follows
  here for the same reason.

  What did not move: the two `github.com/trueagi-io/PeTTa` URLs in the package
  manifest, and ten lines of prose naming the PeTTa project and the engine
  these seats embed, spread over both READMEs, the package description, three
  file headers and three doc comments. Those name the repository and its
  implementation, which is not something a binding owns; the entry above
  carries them.

- **Two lanes stopped measuring what they named, because the JSON they were
  standing on moved into C.** Both counted inferences, and inferences are
  blind across a foreign boundary.

  `test_two_answers_cross_the_wire_without_the_third_being_computed` compared
  the lazy door against the eager one twice, and what made those comparisons
  true was the CLIENT decoding the reply with `library(json)`: an eager reply
  carrying ten thousand atoms cost 1,490,407 inferences to read where two
  atoms cost 1,250. With `engine/json_codec.c` the same run reads 77 for both
  eager sizes, so the counter stopped seeing reply volume and both
  comparisons went vacuous, then red. They count atoms now, which is what
  they were always about and what no codec can blind. The claim the counter
  can still see, that two answers cost the same whatever is behind them,
  stays in inferences.

  `test_the_json_wire_row_is_not_registered_engine_free` put a floor under one
  round trip's inference count, and that floor was the Prolog codec's own
  size. A trip is 72 inferences now and 84,725 under `METTA_C_JSON=off`, both
  of them engine work. It measures the SCALING instead: ten trips cost about
  ten times one, which an engine-free codec cannot do at any magnitude.

- `lib_json`'s `json-encode` answers one line rather than `library(json)`'s
  default `width(72)` layout, and `json-decode` refuses text after the
  document. Both follow from the two callers sharing `engine/json_codec.pl`;
  the compact form is what the network codec has always produced.

- **`bindings/` and `backends/` are one folder, `extensions/`, reached by one
  glob behind one argv token.** The four seats keep their names:
  `extensions/python`, `extensions/node`, `extensions/cmetta`,
  `extensions/mork`, so `metta_extension_loaded(python)` and every other record
  reads as before. What goes is the claim the two folders made, that who DRIVES
  the engine and what the engine CONSULTS are different kinds of thing. They
  are two ROLES one seat may hold, and `entry/2` already named them: the Python
  seat holds both, in two files; the C seat holds both in one; the Node seat
  holds only `host`; MORK only `engine`. Direction of control does not sort
  them either, since the Node transport declares `atom-added` and
  `atom-removed`, which is the engine calling IT, and the Python seat is a
  host, a provider and a target at once.

  `engine/metta.pl` had two control-file globs, one unconditional and one
  behind a `backends` token; it has one, `../extensions/*/extension.pl`, behind
  a token renamed `extensions`. A boot with no token now reads no control file
  at all, which is the pure kernel and a configuration the engine ships in;
  `run.sh`, the packaged CLI, the Python library, the C host and the Node host
  all pass the token, and `engine/main.pl` strips it from argv so
  `swipl -s engine/main.pl -- extensions` still means the demo rather than a
  file of that name.

  Three consequences worth naming. The plunit lane runs each suite once under
  the token instead of twice: the pair used to differ by the backends alone,
  and six of the 39 suites cannot pass in the pure kernel because they test the
  Python seat (measured 2026-08-28; the note in `check.sh` names them and the
  `condition/1` that would buy them back). `tests/prolog/static_checks.pl` sets
  the token before consulting the engine, and its unregistered-seat check reads
  `entry(host, _)` off each control file rather than treating every folder as a
  host binding, so MORK is not asked for a transport it does not have. And the
  Node binding mounts each seat's control file rather than the seat tree, which
  is now load-bearing rather than tidy: `extensions/` holds that binding's own
  `node_modules`.

  409 tracked files carried a path that moved. The sweep was written as an
  explicit pattern list rather than a word replace, because "bindings" also
  means VARIABLE BINDINGS throughout the engine's prose and
  `examples/ch04-spaces-and-matching/04-02-patterns-and-bindings/` is a
  directory whose name ends in it; both are untouched.

  Three lanes that had been reading a stale or absent claim are fixed on the
  way, each the tree's own rather than this change's. The sdist job's wheel
  check globbed the seat root for `*.pl`, a spelling the per-seat folders
  retired in f2387fee, so it has matched nothing since and could not fail.
  `llms.txt` claimed 46 plunit suites after `e80fd4c3` added a 47th. And the
  `[engine, host]` role list `e80fd4c3` introduced carried no
  `policy-inventory-exempt:` line, so that gate had a standing finding.
- **`metta_space_operand/1` reads the `&` prefix before it probes either space
  registry.** It answers whether an atom names a space this engine can query,
  and it sits on nine hot paths: both operand positions of the matcher's leaf,
  `get-metatype`, the three type-candidate resolvers, operation admission, the
  translator's space-expression test and the wire codec, which asks it of every
  atom that crosses to a host. It answered by asking `seam:foreign_space/1` and
  then the native storage registry, and it answers NO for every ordinary
  symbol, which is almost every atom the engine touches. The prefix is not a
  new assumption. It is the engine's own rule at every door that CREATES a
  space, and this predicate was the one place that paid to re-discover it:
  `metta_space_name/1` refuses any other spelling at the creation door,
  `metta_require_space_name/2` refuses it at `new-space` and `inherits`,
  `register_provider` refuses it at the Python door, both wire codecs refuse to
  DECODE a space name without it, MORK's own ownership test is the same prefix,
  and a `State` cell spells its handle the same way. Every
  `seam:foreign_space/1` clause in the tree names a `&` atom. The second clause
  gained the shape test its own registry already guarantees, `S = [_|_]`, since
  a parametric space name is always a nonempty list.
  Measured in the shipped Python configuration, 20,000 iterations against an
  identical loop: `metta_space_operand/1` costs 3 inferences on an ordinary
  symbol where it cost 8, and 4 on a number where it cost 6. The matcher leaf
  `metta_match_atoms/2` costs 17 on two different symbols where it cost 27,
  because it asks twice; `get-metatype` of a symbol costs 12 where it cost 17.
  Through MeTTa, 200 evaluations each, minimum of three: `(unify a b ...)`
  moved 35850 to 32850 (-8.37%), `(get-metatype sym)` 29650 to 27650 (-6.75%),
  `(get-type (undeclared other))` 155454 to 146454 (-5.79%).
  On the counter benchmarks, measured in one worktree on both sides:
  save-load-metta 1386108 to 1286089 (-7.22%), foreign-match 788336 to 750338
  and table-bridge-match 788338 to 750336 (-4.82%), save-load-fast 2287065 to
  2187046 (-4.37%), py-method-call 2050730 to 2000732 (-2.44%),
  annotated-relation 299894 to 294894 (-1.67%), alpha-unique -50, loop-1m -5,
  and no row moved the other way. Each is an exact multiple of 5.00 inferences
  per encoded atom, which is the mechanism rather than a coincidence.
  The twin lane agrees: 126 of the 219 shipped twins get cheaper and not one
  gets dearer. The gated pair is re-priced with the two-sided control its own
  chain records, `03-spaces3` 252 to 242 and `01-identity` unchanged at 2826.
  The prefix is now written into the seam's own declaration and into
  `EXTENDING.md`, because `seam:foreign_space/1` is an open ownership seam: a
  provider naming an atom without the prefix would be answered "no space" by
  every one of those nine paths, quietly. `sh check.sh prolog-static` refuses
  such a name by name, reading both the live database with every library,
  backend and host binding loaded and every hook file's clause heads as text,
  and proves itself against a planted provider before accepting a clean result.

- **The metatype and type-candidate ladders are ordered by what they cost the
  atom they decide most often.** `metatype_of/2` decided an ordinary symbol at
  its twelfth clause, after a seam callback that leaves the engine, a
  grounded-token lookup, a registry probe and a state-cell test. Five of its
  clauses all answer `Grounded` and all cut, so no permutation of them can
  change the answer for any term, which is a stronger argument than mutual
  exclusivity and does not depend on it: `seam:host_object/1` is an open seam
  and may claim a term that also spells a grounded token or a space handle.
  They are now cheapest-first, and the seam, the only one that leaves the
  engine, is last of the five. It cannot move past `list_shaped/1` or the
  `Symbol` clause, which answer something else.
  In `get_type_candidate/2`, `get_type_candidate_in/3` and
  `scoped_type_candidate/4`, the tuple clause led with a negation whose goal
  has a `[F|_]` head, so every symbol called it to have the head fail before
  reaching the free test that says the term is not an expression at all. The
  shape test leads now. Both are pure tests over a term the var clause has
  already made nonvar, so the swap moves no solution and no answer order.
  Measured through MeTTa, 200 evaluations each, minimum of three, with the
  space-operand change already in place: `(get-metatype +)` 27050 to 26250,
  `(get-metatype &self)` 29450 to 28650, `(get-type (undeclared other))`
  146454 to 143256, `(get-type undeclared)` 90652 to 90254. Per call that is
  `metatype_of/2` halved on a grounded token, 8 inferences to 4, and
  `get_type_candidate/2` 12 to 10 on an undeclared symbol.
  **No committed benchmark moves**, and the reason is worth recording rather
  than leaving as a gap: `typed-call`, the workload named for this path, has
  its declared-`Number` checks specialised to `number/1` while the call site
  compiles, so it never reaches either ladder at run time. Nothing in
  `bindings/python/benchmarks/` drives `metatype_of/2` or `get_type_candidate/2`
  in a loop. The inert-clause perturbation control reads identically on every
  workload above, so the movement is the change and not the layout.

- **The Python suite is in chapter packages, the same 22 the examples use.**
  206 modules sat flat in one directory, which is a listing nobody reads and no
  order at all. They are now `bindings/python/tests/chNN_name/`, named in
  Python's own casing, so `ch04_spaces_and_matching` holds the space and match
  tests and browsing the directory is reading the teaching order. Two packages
  are deliberately not chapters: `conformance/`, the arbiters and oracles that
  decide what MeTTa MEANS, where a finding says this engine disagrees with an
  authority rather than that a feature broke, and `repository/`, the tests
  whose subject is this repository rather than the language. Chapters 2 and 22
  have no package, because what they teach is a whole program and the examples
  corpus carries it.
  `bindings/python/tests/data/`, three fixtures outside any scheme, is
  `fixtures/`, the name the repository's own test tree already uses.
  A module one directory down counts one more parent, so 58 `Path(__file__)`
  chains were rewritten; a chain rooted at something that did not move, such as
  `EXAMPLES_ROOT.parents[2]`, keeps its count. 92 citations of a moved module
  across 58 files were repointed, most of them evidence tags in engine sources.
  `CHANGELOG.md` was left alone: an entry records what was true at its release,
  which is also why the examples reorganisation earlier in this series left its
  own seven example-path citations as they were.

- **The notebook tour lives under the Python binding and is written in built
  terms.** `notebooks/tour.ipynb` sat at the repository root while everything
  else about the Python surface was under `bindings/python/`; it is
  `bindings/python/notebooks/tour.ipynb` now, beside the `examples/`, `tests/`
  and `tools/` it demonstrates. Its old form reached the engine through
  `m.run("""...""")` in nine of fourteen cells, which is the one thing this
  surface exists not to make you do: a string has to be parsed before it is
  anything, and it is opaque to the editor, the type checker and `grep` until
  then. Every structural argument is now a term the notebook builds, `m +=
  S.Parent(S[older], S[younger])`, `m.match(S.Parent(V.parent, V.child))`,
  `m.cast(S.Tom, S.Person)`, `m.trace(S["generation-score"](3))`,
  `equation(S.ancestor(V.x)).to(fn.match(...))`, and the one cell that is still
  MeTTa source is the `%%metta` cell, whose whole subject is that a MeTTa cell
  and a Python cell share one session. The tour also gained the two cells the
  library had grown past: `m.answers(...)` listing a bag of answers, and a
  derivation picked by the answer it proves, so the proof shown is the one the
  recursive equation reaches. Cells now carry the `id` nbformat has required
  since 4.5.

- **`tests/` is in folders by kind, and `tests/regression/` is gone.** Twenty
  loose files at the top became `checks/` (the Python gate scripts, each with
  the selftest that proves it can fail, plus the runner model), `shell/` (every
  `test_*.sh`, absorbing the four that sat in `regression/`), `fixtures/` (the
  specializer reproductions, the no-autoload boot, the two parity drivers) and
  `data/` (`example_skips.txt` and the upstream parity baseline). The 46 plunit
  suites are grouped under `tests/prolog/suites/<group>/` by the engine unit
  each one tests. The `.pl` analysis machinery stays at `tests/prolog/`, which
  is a judgement rather than an omission: `surface_walk.pl` is loaded by six of
  them and five are both a script `check.sh` invokes and a library another
  script loads, so a gates-versus-support split would be a false cut.
  A suite two levels down writes paths at two depths, and `tests/README.md` and
  `tests/prolog/README.md` say which is which: a load-time directive resolves
  against its own file, a run-time goal against the working directory, which
  the runner keeps at `tests/prolog`.
- **Every shipped library has its own directory, MeTTa beside Prolog.**
  `lib/` was a flat alphabetical listing of nearly sixty files in which
  `lib_memo.metta`, `lib_memo.pl` and `lib_memo_doc.md` sat far apart and
  nothing said they were one library. They are `lib/lib_memo/` now, and a
  library is the folder. The resolver does the work: a module spec with no
  directory component gets one, so `(library lib_roman)` reaches
  `lib/lib_roman/lib_roman` and `library('lib_builtin_types.metta', P)` reaches
  `lib/lib_builtin_types/lib_builtin_types.metta`, while a spec that already
  names a directory is taken as written, which is what keeps the engine's own
  `builtin_mods/skel.metta` shipped-module spelling working unchanged. Nothing
  a PROGRAM writes changes: `!(import! &self (library lib_roman))` is the same
  line it was.
- **`examples/` is organised by reading order rather than by topic, and the
  order is in the path.** The thirteen topic folders (`basics/`, `control/`,
  `spaces/`, …) become twenty numbered chapter directories following the
  22-chapter spine that also orders the Python tests and the website, with
  sections inside the large ones and a two-digit ordinal on every file, so
  `examples/ch07-control-flow/07-02-case/03-caseconstrain.metta` says where it
  sits without an index. The scheme is the Rust book's: `chNN-slug/` for a
  chapter, a section repeating its chapter's number the way `listing-07-02`
  does, and the leaf keeping the name it always had.
  Two chapters are new content rather than a move. `ch01-getting-started`
  teaches the evaluation first and the checking form second, and says plainly
  that `test` is this implementation's rather than the language's, which
  `KERNEL.md` has classified as a divergence all along while it was
  nonetheless the first thing every reader met. `ch02-programming-a-family-tree`
  is one program in four steps with everything forward-referenced, the recurring
  worked project the spine asks for.
  Every consumer moved with the corpus: `tests/example_skips.txt`, the 219
  twins (whose paths mirror the examples by construction), the twin residue
  table, the upstream parity baseline and its waivers, the engine and library
  sources that cite an example in an evidence tag, `bench.sh`'s
  basename resolution against the flat upstream base, `llms.txt`, the website
  pages, and the C example directories with their sources and READMEs.
  `CHANGELOG.md` is deliberately not rewritten: it is a dated record, and it
  already carried paths renamed since.
- Two published host services now state the SHAPES a caller has to know, which
  were previously discoverable only by experiment. `metta_host_remove_reported/3`
  answers the plain boolean `true` or `false`; the first C implementation
  guessed the atom `removed` and reported every successful removal as a miss,
  silently, because a wrong guess still unifies with a fresh variable. And the
  name list `sread_with_names/3` answers, which `swrite_with_names/3`,
  `sdisplay_with_names/3` and `metta_name_pairs/2` all take, is `Name-Var`
  pairs, `-`/2 rather than `=`/2, with `Name` an atom carrying no `$`; passing
  `[]` is legal and numbers the variables instead, so `(f $x $x $y)` comes back
  as `(f $_0 $_0 $_1)`.

- The wire codec's `p` tag now states which question it asks, and both shipped
  seats ask the engine that one question. `p` is a **species** tag, so it
  follows the engine's own species classifier: `metatype_of/2` decides a space
  with `metta_space_operand/1`, and that is what an encoder asks, so
  `get-metatype` and the wire cannot disagree about an atom. Before this the
  Python encoder wrote `p` for exactly two hardcoded names, `&self` and
  `&petta`, and the C seat rebuilt the whole `metta_space_names/1` registry per
  answer, so the two halves of one codec disagreed: a space made by
  `!(new-space)` crossed to Python as an ordinary `Symbol` and could not be used
  as a space. `CODEC.md` has a section on the rule and its price.
  The ampersand alone decides nothing, which is the part a new binding gets
  wrong. `&not-a-space` crosses as `["s", "&not-a-space"]` because no space
  exists under that name, and a `State` cell, `&state-#0`, is not a space
  either. The wider `metta_space_name/1` test that `(is-space ...)` answers says
  yes to both, because it asks whether a space operation may take the name, and
  that is a different question from what the atom is.
  The price is the other way round: a space's species depends on whether it
  exists, so an atom crosses as `s` before anything creates a space under its
  name and as `p` afterwards. That is the engine's create-on-demand model and
  what `get-metatype` reports too.
  The decoder got simpler with the encoder: Python used to keep its own set of
  the space names `Space` had built and re-read an `s` payload against it, which
  was a third answer to the question and missed every space MeTTa itself made.
  The tag now decides alone. `tests/codec/corpus.json` gained `symbol-ampersand`
  and `space-in-expression`, and the C seat dropped a per-answer space-name list
  that cost a `findall`, `findall`, `append` and `sort` for every atom it
  decoded.

- A future space now exists from the moment its name is handed out, the same
  way `(new-space)` creates before answering. `lib_thread.pl` says a future IS
  a space, and it was not one until something wrote the first answer into it:
  in that window `(get-metatype &future-1)` answered `Symbol`,
  `m.space_names()` did not list it, and a host asking the engine what species
  the atom was got told a symbol, so `!(spawn (+ 1 2))` and every `async`
  operation handed Python a `Symbol` where a `FutureSpace` belongs. All four
  doors that mint one, `spawn`, the async host operations, the pool submit and
  the timer, share the fix, and the timer's own comment already said the
  future exists from the moment it is scheduled.

- `metta.space(...)` takes a `Space` back, so opening one is idempotent
  instead of a `TypeError`. The door answers a `Space` and refused to accept
  one, which only became reachable when an engine answer naming a space began
  arriving as a `Space`: `metta.space(json_decode(text).one())` is how
  `lib_json` and `lib_file` hand a decoded object's space to Python. A dropped
  handle is still refused.

- `metta.MeTTa().space()` now creates the space it hands back, so
  `(get-type ...)` on a fresh anonymous handle is `SpaceType` and
  `m.space_names()` lists it, matching `(new-space)` and what the arbiter
  requires of it. It minted only a NAME before, so the handle Python returned
  answered `%Undefined%` and metatype `Symbol` until something wrote to it,
  and a term carrying it came home as a symbol. The `inherits=` and
  `restricted=` forms are unchanged: their declarations create the storage
  themselves and refuse a child that has already been used. Naming a space
  still registers nothing, so `metta.space("&kb")` with an explicit name and
  `Space("&kb")` are unchanged.

- The kernel's metadata space is `&metta`. It was `&petta`, which named this
  implementation rather than the component the space belongs to, and the
  component names are now settled: the kernel is `metta` and the Python
  bindings are `pymetta`. Every surface that spells the space follows, 654
  occurrences over 122 files, and that reaches the two names derived from it,
  the `new-space` gensym prefix `&metta-space-` and the conformance library's
  `&metta-conformance-`. A program written against the old name reads an
  ordinary empty space rather than the catalog, because nothing has shipped
  under `&petta`: every changelog entry naming it is still unreleased. The
  engine's internal Prolog predicate names followed in the entry below, and the
  Node binding's own copy of the name is untouched pending its own pass.
- Nothing is spelled `petta` any more. The space rename above settled the
  component names; this carries them through everything else, 8,233 renamed
  runs over 552 files: 6,940 `petta_*` Prolog and Python identifiers over 1,169
  distinct names, `PettaError` and the 66 files that raise or catch it, all 27
  `PETTA_*` environment variables, 539 prose mentions, and the fixture symbols,
  temporary-file prefixes and reserved atoms derived from the name
  (`petta-three`, `.petta-save-`, `--petta-dir`, `PETTA-CACHE`, the
  `'$petta_atoms:'` storage-module prefix, the `'$petta_answer'` wrapper).
- **Environment variables are `METTA_*`, and the old spelling is not read.**
  `METTA_PATH` replaces `PETTA_PATH`, `METTA_C_READER` replaces
  `PETTA_C_READER`, and so on for all 27. There is no fallback: a shell or
  script still exporting `PETTA_PATH` now configures nothing, silently, and
  must be updated. The `MeTTa(petta_path=...)` keyword is `metta_path=` for the
  same reason, so a caller passing the old keyword raises `TypeError` rather
  than being quietly ignored.
- `PettaError` is `MettaError`, joining `MettaSyntaxError`,
  `MettaOperationError` and `MettaResultError`, which already spelled it that
  way. Every subclass keeps its own name.
- `EXTENDING.md` documented `PETTA_PROLOG` as the attribute an integration
  package defines while `metta.integrate` has always read `METTA_PROLOG`, so
  the documented recipe could not work. Both now say `METTA_PROLOG`.
- Three names could not move mechanically, because the target already meant
  something else. `petta_boolean/1` in the Ciao contract fixture is the same
  two clauses as the engine's `metta_boolean/1`, and both files load into
  `user`, so the rename would have made SWI discard the engine's definition
  with a "Redefined static procedure" warning that also fails the lane; the
  fixture now uses the engine's. `petta_py/3` is `metta_py_call/3`, because
  `metta_py` is the Python module the same file names in
  `py_call(metta_py:Goal, ...)`. The phrasebook's `petta_inferences` field is
  `metta_fuel`, because it caps inferences where the recorded
  `metta_inferences` counts them, and one spelling for both in one module is
  a trap.
- A twin's pricing declarations now sit at the END of the file, under the `#:`
  run that documents them, and a re-pin appends there. The chain never shrinks
  and every merge adds a paragraph, so on top it buried the example the file
  exists to show: `basics/identity.py` opened with 297 comment lines before its
  first statement, and all 219 twins open with code now. The twins lane reads
  the placement as a finding, and `twin_coverage.py --repin --reason ...`
  measures min-of-three in fresh processes and writes the paragraph at the
  bottom, refusing a top-heavy twin, an empirical envelope, and a move with no
  stated mechanism.
- The Python `+=` write door now classifies semantic scalars before fact
  streams. A built `Expression`, bare atom, text value, mapping, or explicitly
  grounded iterable is one atom; lists, generators, SQL-style iterables,
  dataframe row protocols, and outer tuples of complete rows write one atom per
  item. An empty stream writes nothing. Relative `S.admits(Type)` and
  `S.capacity(n)` values route through the same contract installers as the
  receiver methods, so the next disallowed write is refused. Admission and
  capacity remain ordered conjunctive pre-add checks; this does not claim the
  still-open general P14.23 conflict-merge algebra or classify reaction agenda
  writes as merge conflicts.
- A raw Python tuple now has transparent `Expression` equality and hashing in
  both directions. Equal tuple and Expression values are interchangeable as
  dict and set keys. `Grounded(tuple)` is the explicit opaque-identity spelling
  and no longer compares equal to the raw tuple, preserving symmetry,
  transitivity, and Python's equal-values-have-equal-hashes contract together.
- Close the Python guide's documentation-law gaps with dedicated `S`/`V` and
  execution-location explainers, the strong `collapse` boundary, walrus
  call-time choice and its bound-generator analogy, the non-atomic
  `State.value += 1` contract and lock or `Space.take()` remedies, the Python
  3.12 floor beside 3.13 `copy.replace` and 3.14 t-strings, process-sharing
  boundaries, `ExceptionGroup` atom rendering, and source-only field
  docstrings. Named acceptance tests pin the four runtime-sensitive laws.
- Wide query projections now index variable names once for decoding and row
  construction. Distinct-column joins grow linearly instead of quadratically,
  while rows below 64 columns retain the lower-overhead list path.
- Dropping many compiled spaces now removes support-graph state through
  module-indexed endpoint patterns. Teardown scales with the affected edges
  instead of rescanning the whole remaining graph for every space.

- BREAKING: a foreign space provides only what it declares. A provider
  with no `seam:foreign_capability/2` rows used to be treated as
  providing everything, so a missing hook surfaced as a silent failure
  inside a callback; now declaring nothing provides nothing, and every
  operation on an undeclared capability is refused by name. Providers
  must declare their capability rows; every shipped and fixture
  provider now does.
- A `Space` handle is a `Grounded` species: `isinstance(space, Grounded)`
  is true, matching the glossary's rule that a handle names a live
  engine object and crosses as the grounded atom it is. A handle still
  refuses `.value`, application, and encoding into stored terms, so no
  value-reading grounded branch can mistake one for a boxed Python
  object.
- Rename the reader builtin `sread-command` to `parse-command` across the
  engine, prelude, examples, and the generated `fn` namespace: the verb
  is parsing, and the Python surface's `m.fn.parse_command` now says so.
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
  `space.fn` while keeping bracket names exact. The settled `neg` word expands
  to `(- 0 x)` at live and compiled call doors; unresolved `floordiv` remains
  an explicit refusal.
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
  `metta_py_function_generation/1`. Removing the per-evaluation catalogue
  sniff puts `py-method-call` at 1,503,497,066 instructions, below its
  1,508,773,364 acceptance ceiling.
- `not-provable` costs inferences linear in the recursion depth of the goal
  under it rather than quadratic: the open-call set that the recurrence check
  walks per level is an assoc keyed by a variant hash of the call, so depth
  800 costs 69,006 inferences where the list walk cost 338,974.
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
  `dir(metta)` answers 61 names down from 152, a fresh `import metta`
  loads 9 modules down from 58 and takes 12ms down from 40, and every
  specialist surface (`algebra`, `arrays`, `events`, `wire`, `tables`,
  `paths`, `derivation`, `foreign`, `casting`, and the rest) loads on
  first access under PEP 562. Public atom types use complete Python
  class names: `Symbol`, `Variable`, `Expression`, `Grounded`. Deleted
  without aliases, each with its one door: `new_space`/`fresh_space`
  (`metta.space()`), `count` (`len(space)`), `space_name` (`.name`),
  `register_op` (`op`), `run(using=)` (`with m.bind(...)`), `one`,
  `first` and `stream` (the answer API), `save(space, path)`
  (`space.save(path)`), `val`/root `encode` (`ground` and
  `metta.wire`), `metta.das` and `metta.persistent`
  (`metta.space(backing=...)` and `metta.space(journal=...)`),
  `backend_info` (`metta.engine().info()`), and the root re-exports of
  errors, protocols, events, and proof detail, which live on their
  satellites. Upstream's `python.petta` wrapper is unaffected.

- The supported Python floor is 3.12, raised from 3.11. Every generic
  declaration in `metta` now uses the type-parameter syntax the class shape
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
  than quadratic, in the engine's `(read-form!)` and in the `metta repl` CLI
  alike. Both appended each new line to the whole buffered text and re-scanned
  all of it; the scanner state is now carried from one line to the next. One
  form of 1,600 lines cost 132,673,790,292 instructions and costs 1,497,495,105.
- `metta repl` no longer hangs on two inputs the engine considers finished: a
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
  an `(events <ctx> <delivery> <order>)` atom in `&metta`; delivery is
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

- **`lib_llm` is gone** (user ruling, 2026-08-31: "i disagree with lib llm ...
  later on i will build a library on top of pymetta for llm stuff, so yeah i
  dont want it"). It shipped four provider selectors, a chat call and an
  embedding call over the OpenAI and OpenRouter APIs. What went with it: the
  library, `examples/ch11-python-as-a-notation/09-llm_cities.metta` and its
  skip-list entry, and the mentions in `EXTENDING.md`, `llms.txt` and the
  generated library reference. `tests/conformance/petta/lib/lib_llm.metta` is
  UNTOUCHED, because that tree is upstream's own and the conformance lane
  compares against it as it is.

  Worth recording because it was measured on the way out: `!(import! &self
  (library lib_llm))` RAISED on a machine with no `OPENAI_API_KEY`, because a
  top-level form built an OpenAI client at import rather than at first call.
  Upstream's own copy reads its key inside each call over plain `urllib`, so
  this was ours. The replacement rides the Python surface, where an LLM is an
  ordinary grounded value and needs no library of its own.

- **`extensions/python/lowerings/`, a seam home nothing ever moved into.** The
  folder held one README and no content. It was created by the tree partition
  as the place the Python seat would keep translator rules whose bodies LOWER a
  MeTTa form into a faster shape, so a satellite PyMeTTa repository would carry
  them with it. Three things were true of it and stayed true: every lowering in
  the tree belongs to the ENGINE (23 in `engine/translator_rules.pl`, eight in
  `engine/prelude.metta`) or to a LIBRARY, because a translator rule rewrites a
  MeTTa form and that is language-level work; nothing globbed the folder, so a
  file dropped there would not have loaded, since `extension.pl` declares only
  `bridge.pl` and `metta/shim.pl`; and the `.metta` file it described is the
  rung BELOW the door this seat already ships, `@rules`, which registers the
  same `add-translator-rule!` from a checked Python generator. The seat's
  performance work has never been shaped like a form that compiles badly -- it
  went to the crossing every time, to the predicate door, the C reader and the
  C JSON codec -- so the folder was a bet on a repository split, for content
  that had not been needed, in a format the seat does not use.

- **The test-corpus counts in `llms.txt`.** How many blackbox test files,
  plunit suites or Python twins the tree carries tells a CONSUMER nothing it
  can act on, and the numbers churn: adding one seam regression turned the
  `llms` gate lane red for a figure no reader had wanted. They are gone from
  the document and from `llmsdoc.py`, for the reason already recorded there
  against the engine line count. The rows stay, because WHERE the tests live
  and what shape they take is the part that helps, and that does not move with
  a file. The lane still fails on a planted wrong count, so nothing was
  weakened.

- **`extensions/python/HE/`, the Hyperon-Experimental bridge.** Three files
  registered a grounded atom inside upstream Hyperon so that
  `!(metta (fib 10))` there evaluated on this engine and returned its answers
  as a `superpose`, with `compileme.metta` and `hyperonexperimental.metta` as
  the demo. Its purpose was upstream interop, which carries no weight here any
  more, and nothing ran it: `hyperon` is not a dependency, no test imports it,
  and it was the only directory in the Python tree excluded from `ruff`,
  `interrogate`, `bandit`, `deptry`, `jscpd` and `codespell` at once. The
  rename to the `metta` module had also cost it the distinctness it was built
  for: upstream still carries it as `pettamorph.py` registering a `petta`
  token, while ours had become `mettamorph.py` registering `metta`, colliding
  by name with MeTTa-Morph's own extension module and with minimal MeTTa's own
  `metta` instruction. All six tool exclusions and the `check_spec_status.py`
  scan entry go with it.

- The two dozen flat aliases at the top of `examples/` are gone, along with
  `examples/_fixtures`. Each was a symlink into a topic folder, kept when the
  corpus was first grouped so that older paths still resolved; none of them
  was a program of its own, and every runner already skipped them, `test.sh`
  through `find -type f` and `example_parity.corpus()` through an explicit
  `is_symlink()` filter. What still read them now names the file: the encoding
  lane and `test_metta_examples.py` run `examples/reasoning/measure.metta`
  rather than `examples/measure.metta`, and the `README` links the real paths.
  The upstream parity baseline loses its 24 duplicate entries, which measured
  the same bytes twice under two names.

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
  gone, and `metta` is the only import path. Code spelling the upstream
  checkout layout must import `metta` directly.

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
  one, and the reason is published into `&metta` as
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
- `metta.spaces.object_view(obj)` now presents live Python fields as
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
  lexical free variables, and purity. The facts reflect into `&metta`, replace
  with a clause, and leave when its space is cleared.
- Local annotated assignments in `@define` functions now compile to in-place
  MeTTa type claims. The value binds before the premise runs, and annotation
  syntax resolves without arbitrary `eval` or user-defined subscripting.
- `typing.Annotated` metadata now survives as matchable `(Annotated ...)`
  claims while the base type continues to control arrows, conversion, and
  engine-parameter injection.
- All 44 names installed by `metta.arrays` now carry arity-accurate arrow
  declarations, including defaulted and variadic call forms. The new
  `broadcast-shape` CLP(FD) relation checks or infers NumPy broadcasting
  shapes before an array is materialised.
- Python conversion now carries bare and abstract sequence annotations through
  the same container hook as parameterized builtins. Buffer exporters project
  as zero-copy `Buffer` expressions that retain the original object together
  with shape, format, item size, dimensionality, strides, and access metadata.
  Integration entry points may declare `METTA_REQUIRES`; discovery installs
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
  Five pinned Scallop README programs now ship as executable MeTTa witnesses
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
- The six function-dispatch decisions are catalog data in `&metta`:
  mismatch, no matching head, evaluation order, result determinism, failed
  clause handling, and exhaustion. Each has a shipped default and accepts a
  `(dispatch-policy <function> <axis> <value>)` override that takes effect on
  already-compiled calls. The conforming no-match default leaves the call
  unreduced.
- `&metta` now publishes `(policy <axis> <knob> <default>)` rows for exactly
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
  `&metta`, answering the pre-add hook's own verdict algebra: `(accept)`,
  or `(refuse (does-not-carry <type>))` and
  `(refuse (pool-at-capacity <limit>))` naming the first violated
  contract. `declare_admits` and `declare_capacity` claim a pool's
  pre-add hook with it through a one-line guard equation, and
  `examples/spaces/admission_pools.metta` runs the same judge written in
  MeTTa with a differential asserting the two agree verdict for verdict.

### Fixed

- **A remote gateway authorized one space and executed against another.** A
  request that omitted `space` was checked against the served context's name
  and then run against `&self`, so an authorization callback could approve a
  write that landed somewhere else. Both paths now resolve the same name.
- **A recycled thread identifier could crash the process.** `Runtime` recorded
  its owning thread as `threading.get_ident()`, an operating-system number the
  kernel reuses after a thread exits. A newly spawned thread could inherit a
  dead thread's number, be mistaken for the engine's owner, and take the Janus
  fast path on an engine it did not hold. Ownership is now the live `Thread`
  object, which cannot collide.
- **Compiled Python operators follow Python's data model.** `a + b` in a
  `@m.define` body assumed numbers, so string and list concatenation, set
  difference, percent formatting, and every reflected or in-place dunder
  answered an error atom that then flowed on as data. Untyped operands now
  dispatch through the live protocol. An `int` or `float` annotation keeps the
  pure engine head, so `def f(x: int) -> int` compiles exactly as before.
  Equality stays on the protocol path even when annotated, because `1 == 1.0`,
  `nan == nan` and `-0.0 == 0.0` disagree with the engine relation.
- **A `for` loop over a string, bytes, or dict answered nothing.** The loop
  peeled with `decons-atom`, which has no answer for a grounded String, and
  compared emptiness against the empty Expression. The comprehension form of
  the same iteration was correct, so the two disagreed inside one function.
- **`space |= atom` shredded a built atom into its children.** `Atom` was
  missing from the refusal list while `Expression` registers as a `Sequence`,
  so `space |= S.f(S.a, S.b)` stored three atoms instead of one.
- **A compiled `except` matched on the class name.** An unrelated class that
  merely shared a name was caught, and `Timeout`, `Error`, `ValidationError`
  and `ConnectionError` are all shared names. Arms now compare class identity.
- **`limit=0` ran unbounded** at four query entry points and, separately, in
  `metta.algebra.count_tagged`, whose own validator advertised zero as legal
  before collapsing it into the engine's no-limit sentinel. Zero is now
  refused everywhere with one message.
- **`speculative()` kept writes taken lazily**, and `Space.derivation` escaped
  it entirely: its proof search ran outside the shared capture, so a
  diagnostic inside a speculative block left its writes in the engine-global
  space.
- **A batch write bypassed the provider's policy gate.** `foreign_add_many`
  consulted the gate for the first atom only, so an atom a provider declines
  landed whenever it was batched behind another.
- **One raising watcher starved every later subscription** of the event that
  had already committed.
- **A blocking engine call on a bare thread froze every other Python thread**,
  including the one that would have unblocked it.
- **A failed async landing left its future pending forever.** A publication
  failure was logged and discarded while the context was released, so an
  awaiting caller had nothing to wake it. Failures now settle the future as an
  error, and process controls propagate instead of being swallowed.
- Subscriptions outliving their event loop, abandoned channel queues,
  `py-atom` declarations, and timed-out remote worker requests all release now
  rather than accumulate. `assuming()` removes every hypothetical even when
  one removal fails.
- A rejected guarded event no longer ends a blocking stream early, native
  handles round-trip through the public wire codec, and `resolve()` reports a
  module that exists but fails to import instead of blaming its prefix.


- **A trailing underscore now escapes a keyword instead of becoming a
  hyphen.** `S.not_` answered the symbol `not-`. No head in this tree ends in
  a hyphen, so that symbol could never match anything and nothing said so.
  PEP 8's trailing underscore is the escape for a name Python's grammar
  reserves, and the naming ladder ranks it above the mechanical
  underscore-to-hyphen map, which the tree already honours elsewhere
  (`RouteKey.global_.value` is `"global"`). `S.not_` is now `not` and
  `S.lambda_` is `lambda`, while `S.car_atom` is still `car-atom`, `V._` is
  still the anonymous variable, and `S["not_"]` still reaches a head that
  really does end in an underscore. The cause was a second copy of the map
  inside the atom namespace rather than a call to the one canonical function;
  the copy is gone.


- **Four documentation facts that were wrong.** `DEVELOPING.md` said the
  floor was Python 3.11 where `requires-python` is `>=3.12`; the
  getting-started guide counted thirteen Python examples where the tree
  holds 24; the README pointed at "Spaces backed by anything" as being
  below the section that links it when it is above; and the Python
  examples README tabulated 22 of its 24 programs, omitting
  `integration/cmetta_space.py` and `reasoning/literature_discovery.py`.
  The README's own count of 233 gate-run programs was checked against
  `len(example_parity.corpus())` and is correct.


- **`AsyncMeTTa.define` forwards `prolog=` and `name=` on every shape**
  instead of silently discarding the Prolog source when a function rides
  the same call, or the name on the prolog-only form.
- **An abandoned `FutureSpace` warns instead of spinning silently**: the
  garbage collector emits asyncio's kind of ResourceWarning when a future
  dies unobserved, while waited, settled and cancelled futures stay
  silent; the computation itself keeps Python's own future semantics.
- **`Space.drop` closes an owned provider even when unregistration
  raises**, so a failing foreign provider cannot leak its connection.
- **Compile refusals render their file, function, line and an exact
  caret** for every statement wall, not only expression walls: the
  compiler derives the coordinates once at its boundary from the held
  source, and the caret gutter is width-matched to the number gutter,
  fixing a one-column misalignment every rendered caret had.
- **A remote mutation's timeout is documented as UNKNOWN, not failed**:
  the server may commit after the client stops waiting, and the provider
  door now says so; exactly-once delivery via idempotency keys is the
  ledgered follow-up.

- **Python's try, raise, dicts, sets, type aliases and the global pragma
  compile.** A compiled body now carries `try`/`except`/`else`/`finally` on
  the engine's own error algebra: `raise` produces through the prelude's
  `throw`, `catch` reifies the host lane, `if-error` splits, the new
  `except` runtime test walks MRO names so custom hierarchies match as
  `isinstance` would, and `error-payload` hands `as e` a live instance. A
  dict literal lowers to lib_dict's dict-space (a SPACE of `(key value)`
  atoms, with `d[k]`, `in`, `d[k] = v`, `del`, `len`, `.keys()` and the
  comprehensions riding the library's own doors, and every space operation
  lawful on the result), a set is a dict to True, `type X = int` becomes
  the rewrite rule it reads as, and `global` reads and writes the
  definition module through a grounded reference. Bindings inside a try
  trap error data and produce it, so an assignment whose right side errors
  aborts to the arms exactly as Python's raise would.

- **The bitwise family and floored division are engine operations.**
  `bit-and`, `bit-or`, `bit-xor` and `bit-not` complete the family the
  shifts opened, exact integer operations on SWI's own instructions, and
  `floor-div` is SWI's `div`, Python's floored quotient exactly, with the
  same DivisionByZero error data integer division answers. A compiled
  body's `&`, `|`, `^`, `~`, `<<`, `>>` and `//` lower to these heads and
  pay no host crossing.

- **Unknown host expressions island instead of refusing.** What the
  compile vocabulary does not lower natively (an unregistered call, a
  host attribute read, a method on a local, keywords against a host
  callable) crosses as the same visible application-time island `py(...)`
  spells, with nothing executed at decoration time and the loud refusal
  kept for names that resolve nowhere. The lint layer records implicit
  islands under the author's own spelling.

- **`alpha` is the =alpha spelling.** `alpha(x, y)` in compiled bodies,
  `Atom.alpha(y)` on the atom tier (beside `eq`/`ne`, the same
  nearest-relative rung), and `fn["=alpha"]` remains the exact door;
  `alpha_eq` still answers the immediate Python-side check.

- **The MeTTa context is the third generated mirror.** The context tier's
  doors (`run`, `load`, `eval`, `match`, `add`, `remove`, `define`, `op`,
  `stats`, `limits`, `trace`, `speculate` and the rest) are generated
  from Space with signatures, overloads and docstrings carried verbatim,
  replacing a hand-written subset typed `(*args: Any) -> Any` that erased
  every overload and missed doors (a context that could define but not
  eval). The root's lazy exports gained their static faces, so
  `metta.MeTTa` and its siblings type-check under py.typed instead of
  reading as Any.

- **A cursor pulls a chunk of answers per engine crossing.** The lazy doors,
  `stream()` and every iterated `Answers`, crossed the Python/Prolog boundary
  once per answer, and the crossing cost as much as a plain enumeration's
  engine work per answer, so a drain spent half its time in the boundary.
  A cursor now asks for one answer on its first pull and doubles up to 64,
  the same opening TCP and a growing vector use: taking one answer of an
  infinite stream still costs one answer's work, taking k computes fewer
  than 2k, and a short chunk remains the whole of the exhaustion signal, so
  nothing looks ahead past the doubling. Materialised both ways, draining
  ten thousand answers went from 27.9x the eager door to faster than it at
  every size, and a one-answer call costs the same 218 inferences it always
  did. A budget that trips mid-chunk discards that chunk's collected prefix,
  which is the accepted price of the crossing win; raising the budget is the
  diagnosis path and delivers more.

- **The shrink ledger.** `KERNEL.md` classes the engine's 58 translator heads
  as primitive or derived and makes every fused derived form say why; the
  Python surface now carries the same ledger over its 110 doors, generated
  from the code by `tools/ledger.py` and gated. A door expressible by another
  public door must say what it buys the caller, and the reasons live in one
  file rather than sixteen docstrings.


- **Five working constraint operators were invisible to the type surface.**
  The engine implements and registers `#//`, `#=`, `#\=`, `#=<` and `#>=`
  alongside the nine `#` operators `lib_builtin_types` declares, and all five
  evaluate correctly, but none carried a type: `(get-type #<)` answered
  `(-> Number Number Bool)` while `(get-type #=)`, `(get-type #>=)` and
  `(get-type #//)` each answered `%Undefined%`. Anything derived from the type
  surface (checking, `get-type`, the generated library reference) could not
  see them. They are declared now, and each answers its arrow.

  Declaring them was enough to find a second gap, because a declared type
  enrols a name in the engine's own input-guard probe: it reported `(#= $x 1)`
  binding its own input and `(#=< $x 1)` answering true, where every guarded
  builtin refuses an unbound argument by name. Both are the constraint doing
  its job, so the four join the relational family `#+` and its siblings were
  already in. The classification was what was missing, not a guard.

  Found by asking a different question: comparing this engine's whole callable
  surface against upstream PeTTa's, 309 names through the engine's own
  `engine-knows/2` rather than by reading source. All 32 of upstream's
  translator special forms are here, `once` among them.

- **The C branch-return analyzer was silently absent on every cold tree.** A
  unit consulted into an umbrella has its directives stored in the UMBRELLA's
  `.qlf`, so `prolog_load_context(directory, D)` in
  `engine/translator/runtime.pl` answered `engine/translator/` while
  `translator.pl` was being consulted and `engine/` once `translator.qlf`
  served it. `build.sh` writes `engine/mbr.so`, so a boot with no `.qlf` on
  disk looked one directory too deep, found nothing, and ran the Prolog pass
  with the artifact sitting beside it. Nothing said so: the differential suite
  is CONDITIONED on the analyzer being active, so it skipped rather than
  failed, and `sh engine/test.sh` ran 5 tests on a cold tree and 8 on a warm
  one with no other difference. The engine's own source directory is recorded
  once by the umbrella, whose load context is `engine/` in both modes, and the
  unit reads that. A static rule now refuses the shape for every file below
  `engine/`, with the top-level files exempt for the reason that makes them
  safe.

- **The Python binding no longer takes a variable's stack address as its
  identity.** `metta_py_encode/2` spelled a variable with `term_to_atom/2`,
  and SWI derives that spelling from the cell's stack offset:
  `iref = ((Word)p - (Word)gBase)*2` [source:
  `swipl-9.3.33/src/pl-write.c:127-140`, `var_name_ptr()`]. An offset moves
  when the cell moves and is handed to whatever lands there next, so the name
  this boundary used as an identity was neither stable nor unique, and both
  directions bit:
  - one variable crossed under two names inside a single encode.
    `Space.derivation` of a five-deep `(fact 5)` returned
    `(= (fact $_17642) (if (> $_17642 0) (* $_17642 (fact (- $_2528 1))) 1))`,
    whose free `$_2528` is not the variable the head binds, so substituting
    the call left `(- $_2528 1)` and evaluating it raised the CLP(FD) refusal
    instead of answering. One held cell answered `_9162` before a collection
    and `_32` after;
  - two variables crossed under one name. That is the P14.4 residue entry
    `answers that carry different variables arriving in Python under
    different names`, and it is now retired: a match over two separately
    sealed rules answered `($_56584 ok)` twice and now answers `($_1 ok)` and
    `($_2 ok)`, so `m.eval` and the row door agree with `collapse`, which
    gathers in the engine and always kept them apart;
  - an operation's decode table was rebuilt from the arguments AFTER the
    crossing while the names Python held had been written BEFORE it, so a
    collection anywhere in encode-call-decode stopped a returned variable
    resolving to the caller's.

  A name is now MINTED from a session counter and recorded in a map threaded
  through the encode. The map is what keeps one cell on one name inside a
  crossing, which the printed form could not; the counter is what keeps two
  cells apart across crossings, which numbering a term's own variables could
  not. Every decode that has to find the caller's variable again is handed
  the map the encoder built rather than rebuilding one:
  `metta_py_encode_arguments/3` encodes a call's arguments under one map and
  hands it to the reply's decode, an inverse's answered tuple decodes under
  one table, and a query row's columns share one. The engine is unchanged;
  this was the binding disagreeing with the convention `engine/writer.c` and
  `engine/tracer.pl` already hold, that a variable's identity is answerable
  only by comparison and never by where it sits [tested:
  `shim_wire_variable_sharing`, `shim_answer_form`, `shim_relation_form`,
  `python_answer_residue`,
  `test_two_answers_carrying_different_variables_arrive_under_different_names`,
  `test_two_rows_carrying_different_variables_stay_different`,
  `test_a_recursive_proofs_equation_keeps_one_variable_per_source_variable`,
  `test_an_inverse_answers_one_variable_in_two_positions`].

  The Node binding's `metta_node_encode/3` still spells a variable the same
  way and has the same exposure; it is not changed here.

- **The space conformance kit compares two atoms renamed apart.**
  `metta.testing`'s `_same_atom/2` compared printed forms, which answers only
  while a stored atom prints the same on two crossings. Its own docstring says
  a variable's name does not survive storage, and `_renamed_apart/1` beside it
  already normalises an enumeration for exactly that reason; the comparison
  now uses it. A provider whose store hands the same atom back under a
  different variable spelling read as a store that had changed under the kit
  [tested: `test_mapped_passes_the_conformance_kit`].

- **A scoped `with-pragma!` puts every setting back, whatever happened to the
  ones before it.** The scope armed its restore on `setup_call_cleanup/3`'s
  SETUP, which SWI runs before the cleanup exists: a two-key scope whose second
  write raised left the first key set engine-wide with nothing to put it back.
  The undo list is now read before any write and the writes happen inside the
  protected region, and the restore itself is total, where `maplist/2` used to
  abandon every key after the first one that raised or failed. The scope's own
  error still outranks a restore failure, which is reported beside it rather
  than replacing it, the rule try-with-resources and `ExitStack` keep. Neither
  path is reachable through a public door today, because no key's write can
  fail; planting a raise for the second key of a two-key scope leaves
  `max-stack-depth` set under the old spelling and nothing set under this one.

- **A citation may name the file beside the one that wrote it.** The evidence
  lane resolved a claim's path only against the repository root, so
  `extensions/cmetta/cmetta.h` citing `tests/test_cmetta.c` -- the file next to
  it, and what a reader of that seat types -- read as naming nothing. A path now
  resolves from the root first and from the citing file's own directory second.

- **The C seat's claims are checked.** `extensions/cmetta/*.c`, `*.h` and `*.pl`
  join the evidence lane's scan, which reads a C case as a `static <type>
  test_<name>(...)` function that `main()` CALLS: one it merely defines is dead
  in the way an uncollected pytest function is, and is reported the same way.
  The runner model follows the seat's `test.sh` through `make test` to the
  sources it builds. Twenty-one claims in that seat's header had carried commit
  pins and named tests with nothing reading them.

- **The example emptying a space no longer reaches nine chapters forward.**
  `examples/ch04-.../06-spaces_removeallatoms.metta` used `car-atom`, which
  chapter 7 introduces, to show that the removed operation no longer reduces. It
  compares the collapsed call to the call itself instead, which says the same
  thing in chapter 4's vocabulary and stays true in a host's own home space,
  where comparing printed text froze whichever name that world uses.

- **Cancelling around an acquisition releases what the worker finished.**
  `asyncio` delivers a cancellation at an await point, and `metta.aio` awaits
  the worker's answer, so a cancel that landed after the worker had attached
  the engine, registered a standing query or installed assumed facts left the
  resource live with nothing holding it: one leaked worker thread per cancelled
  `connect()`, an invisible live subscription per cancelled `watch()`, and
  facts that stayed installed for a cancelled `assuming()`. The commit point is
  now shielded, so the acquisition always completes, and a cancelled caller
  releases what it can no longer own before the `CancelledError` continues.
  A cancelled `connect()` also refuses the worker it launched, so the thread
  detaches its engine instead of living to interpreter exit.

- **A close records success only after it achieves it.** `aclose()` on an async
  cursor or subscription, and `RemoteCursor.close()`, marked themselves closed
  (and the remote one discarded its cursor token) BEFORE the release, so one
  transient failure left the resource live with the only handle that could
  release it already thrown away, and every later close returned at the flag.
  Each now releases first and records afterwards, so a failed close is
  retryable; the async ones complete their release even if the caller is
  cancelled.

- **A counted lazy result releases the engine its count retained.** An
  effect-bearing goal's `len()` holds its answers in an SWI engine so the
  values cost no second evaluation. That engine's handle lived outside the
  answer generator, and closing a generator that was never started runs no
  `finally`, so a view that was counted and never iterated leaked the engine
  and the whole answer bag for the life of the process.

- **An async event queue is published only once its registration succeeded**,
  so a failed registration no longer leaves consumers waiting forever on a
  queue nothing owns, and the stream's terminator reaches a consumer whose
  queue is full instead of raising `QueueFull` out of the close path. The
  async subscription also takes the same `queue_max` check the synchronous one
  takes, so a bound no comparison can be true against is refused at the door.

- **A server that could not stop its worker leaves its answer cursors alone.**
  `Server.close()` released every cursor even when the engine worker had not
  stopped, which closes a cursor out from under a request that may still be
  reading it; it now says so and leaves them to the next close. Releasing many
  cursors no longer abandons the rest at the first failure, and `GET /health`
  answers an authorization hook's own failure as JSON instead of dropping the
  connection, which a client cannot tell from a network fault.

- **The same-process attach guard covers the addresses it actually serves.** A
  server bound to `0.0.0.0` was registered under that literal alone, so
  attaching the same server through `127.0.0.1` or `localhost` walked past the
  guard into the deadlock it exists to refuse. The guard now recognises a
  wildcard bind by asking the operating system whether the URL's host is one of
  this host's own addresses, and it also takes the addresses a caller is ABOUT
  to serve, so a manifest whose `attach` form stands above the `serve` form
  that binds its port is refused rather than accepted in one order and refused
  in the other.

- **A candidate whose instantiation is a rational tree crosses as the stored
  atom.** Matching binds raw, so a repeated pattern variable can bind to a term
  that contains it, and no finite tagged form spells that instantiation. The
  eager `/match` door dropped such a candidate silently, which is the
  under-approximation the protocol forbids; both doors now take their
  candidates from one linearised cursor, filtered back by the engine's own
  re-unification, so the answer set is exact and finite. One stored atom also
  reads back as one atom: the wire names an answer's variables by first
  occurrence, where the engine's own name is a stack offset that moved with
  every match the server ran.

- **A function change no longer pays for tables that no longer exist.**
  `lib_tabling` invalidated by `abolish_all_tables/0`, which walks the whole
  variant trie, and that trie keeps a variant for every table the process ever
  built: after one space tabled a 200,000-answer recursion and was dropped,
  every later equation change still walked all 200,000. Measured 2026-08-31,
  one equation change after a dropped table of N answers cost 2N inferences
  (10,353 at N=5,000; 40,355 at 20,000; 160,359 at 80,000) and now costs 377 at
  every size. The invalidation itself is unchanged in scope for MeTTa's own
  tables; `tests/ch18_performance/test_tabling_control.py` went from 162 to 8
  seconds.

- **A space name comes back only when it is free.** Dropping a context while a
  handle to its home space is still alive pooled the name, and the surviving
  handle then wrote to it and brought it back to life, so the next `MeTTa()`
  was handed a live name and the engine refused it. The pool is now scanned
  against the engine's own used-check rather than trusted.

- **Attaching a space this process serves refuses immediately instead of
  hanging for the whole transport timeout.** Janus holds the GIL across a
  Prolog call, so while one thread is inside an evaluation no other thread can
  run Prolog whatever engine it attached, and an attached space is only ever
  matched from inside an evaluation. Measured before the fix: the client timed
  out after 30 seconds, the serving side then died on a broken pipe, and the
  caller saw `the engine could not accept this call's inputs`, which names
  none of it. `attach` now refuses at the door and names the transport that
  does work in one process, the `Gateway` that runs on the calling thread.
  The guard is on the address, so an ordinary remote URL still attaches, and a
  plain HTTP call to the same server from OUTSIDE an evaluation was measured
  answering in 0.00s and is not refused.

- **Four engine documents said things that were no longer true, and one of them
  contradicted itself.** `EXTENDING.md` section 4 stated the annotated
  `@m.define` row costs 11.00 inferences as a current fact, while the cost
  table three hundred lines above says 11.00 was the reading BEFORE the
  compiler specialised the check and that the row now reads the same 5.00 as
  the unannotated one, because SWI compiles `number/1` to a VM instruction it
  does not count. A reader who found section 4 first concluded annotating costs
  more than twice what it does. `DEVELOPING.md` told a contributor to
  `cd python` in five places, which has not existed since the tree partition
  moved it to `extensions/python`, so every measurement command in that section
  failed on the first line. `CODEC.md` sent a binding author to "EXTENDING.md
  section 5" for the in-process space seam, which is section 6; section 5 is
  reader token classes. And a CHANGELOG entry cited an absolute workspace path
  for the vendored CeTTa checkout, which the tracked-path check refuses.
- **The engine documents were rewritten for density.** The same rule was being
  re-derived in full at every site that needed it: the cut rule (event seams
  run every handler through `forall/2`, ownership seams may cut after a guard
  that proves the request is theirs) was explained twice at full length, the
  partial-application trap four times, the `limit` pushdown story twice. Each
  is now stated once and referred to. The `extension.pl` control-file
  vocabulary is handed to `extensions/README.md`, which owns that contract,
  rather than duplicated. Verified against what the page is actually held to:
  all 55 seams declared in `engine/ext_points.pl` still appear, both cost
  tables keep the headers and row labels `test_the_extension_cost_tables_match_the_committed_pins`
  parses, and the two headings `engine/metta/types.pl` and
  `engine/ext_points.pl` cite BY TEXT survive verbatim.

- **A call whose input the engine could not accept failed the NEXT call
  instead of its own.** A Python string carrying an unpaired surrogate -- what
  every `surrogateescape` decode produces, so any filename whose bytes are not
  UTF-8 -- raised janus's bare `SystemError`, and the Python exception it set
  stayed PENDING in the engine: the next call, however unrelated, raised it as
  its own, and the call after that was clean. On the remote server that made
  one peer's malformed payload fail a different peer's request. All four doors
  (`once`, `apply`, `do`, `iter`) now make the failure local, the way a
  database client discards a connection's pending results after a framing
  error rather than letting the next statement read them: one sacrificial goal
  absorbs the pending error, then the call raises for its OWN input, naming
  where in the structure the text sits (`Value['answers'][1]['x']` contains an
  unpaired surrogate at position 0). Nothing is spent on the succeeding path.
  Reproduced on the public surface first: at the previous tip
  `space.run("!(+ 1 <lone surrogate>)")` raised `SystemError` and poisoned the
  next `run` [tested: `test_text_with_no_utf8_encoding_is_refused_by_kind`,
  `test_a_refused_crossing_does_not_fail_the_next_call`,
  `test_no_door_leaves_the_next_call_carrying_the_refusal`].

- **`space.eval` handed back janus's own exception class instead of the
  caller's.** The predicate doors (`apply_once`, `cmd`) leave a Python
  exception raised inside the engine pending where the goal-string door clears
  it, and the next janus call on that path is janus's own
  `PrologError.__str__`, which runs `message_to_string/2` to render the very
  error being classified. The classifier died on the pending error and the
  caller received a raw `janus_swi.janus.PrologError`. `eval` has crossed on
  the predicate door since `1ec64474`, and nothing caught this because the test
  that pins the contract drives `run()`, which sat on the other door: measured
  at the previous tip with both files untouched, `run` raised `MettaError` and
  `eval` raised `janus_swi.janus.PrologError` for the same provider refusal.
  `Runtime._resynchronise` absorbs the pending error before classifying, and
  the sibling test drives the same refusal through the term door [tested:
  `test_an_enumeration_refuses_answers_through_the_term_door_too`].

- **A value that contained itself took the process down.**
  `metta._json.dumps({'a': 1, 'self': <itself>})` was SIGSEGV, core dumped,
  exit 139. Every other door hands a Python container over BOXED, as
  `['o', Box(...)]`, and a boxed object crosses by reference without being
  walked; this door passes its value transparently, so janus converts it by
  recursing through it and a container holding itself takes the C stack. A
  payload nested 20,000 deep crashes identically with no cycle. A C stack
  overflow cannot be caught from Python, so unlike the two above this cannot be
  recovered from after the fact and has to be refused before the call, which is
  a cost on the succeeding path and was priced rather than assumed: a universal
  guard on every container-carrying call measured +15.5% on the hot path and
  was rejected; on this one transparent door it measures +88.9 microseconds,
  16.8%, back to back in one process against the same call with the guard
  neutralised. Kept on by default with no opt-out, which is the tradeoff
  CPython's own `json` makes, where `check_circular` defaults to True and every
  caller pays it. Detection is by the CURRENT PATH rather than by everything
  visited, because a value merely REACHED twice is a DAG and legal -- a
  visited-set reading rejects `{'a': shared, 'b': shared}` -- which is why
  `bridge.pl`'s `metta_py_cycle_check/3` passes its ancestors down as `Seen`
  and `json.dumps` keeps the same thing in `markers`. Recursive rather than a
  manual stack, 55.23 against 84.04 microseconds, which also puts the depth
  hazard behind the same mechanism: Python raises a catchable `RecursionError`
  exactly where janus raises SIGSEGV [tested:
  `test_json_codec_refuses_a_value_that_contains_itself`,
  `test_json_codec_refuses_a_value_nested_too_deeply`,
  `test_json_codec_encodes_a_shared_value_reached_twice`].

- **The freshness gate read only Prolog, and the loader that mattered most is
  C.** `extensions/cmetta/cmetta.c` builds its consult as a C string and the Node
  seat builds one in TypeScript, so a walk over `*.pl` alone would let a HOST
  SEAT drop the purge without a word, which is where it matters most: a seat's
  users are not reading the engine's test suite. The walk now covers `*.c` and
  `*.ts` as well, and skips each language's comment markers because the engine's
  own prose names both files constantly. The remedy it prints is spelled in the
  file's own language; a Prolog directive printed into a C file is a gate that
  does not know what it is looking at, and the selftest fails if it is. Sixty-two
  loaders now, and `extensions/node/src/engine.ts` is exempt by name for a real
  reason: it mounts the engine's sources with `*.qlf` and `.qlf-stamp` filtered
  out, so it boots from source and no artifact can go stale under it.

- **A C program could run the engine's previous compile, and fixing that made
  its boot 10% cheaper.** `mt_open()` consulted `engine/metta.pl` directly. The
  engine's units are consulted by umbrellas, so `engine/spaces/foreign.pl`
  compiles into `engine/spaces.qlf` and SWI's staleness check, which compares an
  artifact against its immediate source, never sees a unit edit. This was the
  only host seat with that hole: the Python seat consults `engine/main.pl`,
  which loads the purge, and the Node seat mounts engine sources with the `.qlf`
  files excluded and boots from source by construction. `mt_open()` now consults
  `engine/qlf_boot.pl` first.
  The counters moved more than the fix needed, and each move has its own arm.
  Boot reads 1,961,745,924 retired instructions with neither, 1,735,389,090 with
  `encoding(utf8)` alone and 1,761,836,831 with the whole of `qlf_boot`: the
  flag is worth −11.5% and the purge machinery costs about 26M of it back, plus
  6,955 inferences for globbing the artifact set and reading its stamp. The
  reason the flag matters here and nowhere else is that this seat consults the
  umbrella with an explicit `.pl`, so it is read from SOURCE, and without the
  flag that read goes through the locale's multibyte conversion.
  `error-ball` improves 1.70% and `term-in` costs 0.46% more, and neither is the
  flag: both sit within 0.05% under the encoding arm and move only under the
  whole of `qlf_boot`, which also pins `user_output` and `user_error` to UTF-8.
  One writes error text through those streams and the other runs the C writer
  through `metta_c_show`.
  `extensions/mork/bench.sh` gained the same freshness the other way round: one
  unmeasured `engine/main.pl` boot before the measurement, which is the line
  `check.sh` already runs before its lanes. Both halves of it are load-bearing
  and each fails differently. Loading the purge inside
  `extensions/mork/benchmarks/workload.pl` puts it in the MEASURED process,
  worth +25,600 instructions on `mork-native-match-first-500`; purging without
  regenerating measures a source boot, which moves `mork-batch-add-500` by
  −3.6%. The workload declares its exemption in place.

- **A red row in the C benchmark could not tell you whether it was about this
  seat's tree.** A C host boots with the `extensions` token, so every seat whose
  declared needs hold loads into the process being measured, and a seat's Prolog
  joins the engine's shared multifile seams rather than sitting beside them: the
  Node bridge's own `seam:foreign_space/1` cost one inference on every space
  operation, consulted by the matcher, the type resolvers, the translator and
  the codec. So a seat edited since the pin was taken can move a counter here
  with no change in this seat at all, and the row reads as a regression in the
  wrong tree. `counter_configuration` recorded which seats LOAD and nothing
  about what they contain, so nothing said otherwise.
  A failing row now names any loaded seat whose declared Prolog differs from
  HEAD, following `entry/2` out of each `extension.pl` and the loads those files
  make inside their own seat. Against HEAD rather than a stamp in the baseline,
  deliberately: a stamp would REFUSE every comparison while a sibling seat is
  being worked on, which is a false failure this seat would be inventing, and it
  would need re-pinning where this needs nothing. It is read only when a row has
  already failed, and it answers the question a reader of a red row actually
  has.
  The occasion for it was an attribution that turned out to be wrong, which is
  worth recording next to the fix: `cursor-step` and `term-in` sat outside their
  0.1% instruction band with inferences exactly on pin, reverting every file of
  this seat left them equally red, and the Node bridge had just gone from 5 to
  18 seam clause heads. On a quieter box both returned to within 0.010% of a pin
  taken before any of that: they are multi-modal, with gaps near 0.1% that
  straddle their own band. A control that removes your own change separates
  "mine" from "not mine" and says nothing about which of the others it was.

- **Two C benchmark rows carried a band narrower than their own measured
  noise.** `measurement_conditions` recorded a battery-minimum spread reaching
  0.129% and then concluded that the instruction pins "held through every load
  level seen here", while `cursor-step` and `term-in` carried the 0.1% default.
  A band below the noise floor must go red for no cause, and both did. Their
  minima cluster in two modes 0.127% and 0.113% apart, each mode stable within
  itself across three to seven consecutive batteries, inferences exactly on pin
  throughout, and both modes reproduce with every file of this seat reverted, so
  the modes are layout rather than work. Each row now declares 0.15% beside that
  measurement; the other four held at 0.1% and keep it. The widened band still
  fails: a planted 0.2% regression reds it.

- **A suite could pass against the previous compile of whatever unit it was
  testing.** The engine's units are consulted by umbrellas, so
  `engine/spaces/foreign.pl` is compiled into `engine/spaces.qlf` and there is
  no `engine/spaces/foreign.qlf` at all. SWI's own staleness check compares an
  artifact against its immediate source, so editing a unit leaves the
  umbrella's `.qlf` fresh by mtime and the OLD code is served.
  `engine/qlf_boot.pl` is the purge written for exactly this, and its header has
  said so since 2026-08-25, but only `engine/main.pl` and `engine/bench.pl`
  load it. Every one of the sixty files that loads `engine/metta.pl` directly
  reached neither: forty-four plunit suites and fourteen analysis scripts.
  `check.sh` warms one boot through `main.pl` before its lanes, so the gate was
  never affected. What was affected is the two workflows that skip it and that
  `tests/README.md` documents: one suite run by hand, and `engine/test.sh` on
  its own. Measured by planting a `format/2` directive in
  `engine/spaces/foreign.pl` after a full boot: a suite run the old way does not
  see it, the same suite loading `engine/qlf_boot.pl` first does, and both exit
  0 either way. It cost this session an A/B that read a 0.0000 difference
  between two variants of a predicate, because both runs executed the same
  stale compile.
  Every direct loader now loads the purge first, with the same relative prefix
  so the pair resolves from one directory, and
  `tests/checks/check_qlf_freshness.py` refuses a new one that does not. It has
  an in-place door, `% qlf-freshness-exempt: <why>`, for a file that means to
  measure the artifact set rather than use it. The selftest plants a missing
  purge, a late one and a mismatched prefix, and neutering the gate turns all
  three red plus the by-name exemption case.

- **A cursor budget's documented cost was half its real one, and the real one
  came down by a quarter once it was measured.** `engine/metta/control.pl`
  recorded the cumulative inference budget as costing two inferences per
  answer over the per-solution limiter alone, with three percentages derived
  from that figure. It cost four. Two independent harnesses agree, one driving
  an SWI engine and one driving `findall/3` on the calling thread, identically
  at answer costs of 407, 31 and 6.
  The wrong number has a traceable origin: the C seat's original host-side
  meter made two `statistics/2` CALLS per pull, and a count of instrumentation
  calls was carried across into the engine as a count of inferences when the
  mechanism moved inside the engine goal. Nothing re-measured it because
  nothing could, since the number had no test.
  It also turned out to be reducible. Four semantically identical shapes were
  raced, and the one that spells the comparison so the COMMON outcome is the
  then-branch costs three rather than four: SWI charges an if-then-else one
  more inference when its condition fails than when it succeeds, and
  within-budget is the common case. That is one inference off every answer of
  every bounded cursor, in both seats. Three is the floor for this shape, since
  the two-inference variant drops the throw and merely fails, which would end a
  spent cursor quietly instead of reporting its bound.
  No pinned count moves, which is why it went unnoticed for so long: the charge
  is spent inside the cursor's own engine, where no host counter sees it.
  `query-limit-guarded` passes `inferences=50,000,000` over 5,000 rows and
  holds its pin, where a host-visible per-answer charge would move it by 5,000.
  Both facts are now tests rather than comments, in
  `tests/prolog/suites/evaluation/inference_budget.plt`. The cost test asserts
  the affine relation `Delta = 3 * Answers + 1` rather than dividing, so a
  charge that is not a fixed constant fails instead of rounding into one; the
  mechanism behind it is pinned separately by a probe that holds no copy of
  shipped logic and so cannot drift out of step with it. Six evidence tags that
  cited deleted scratch files under `ai-tmp/` now cite those tests instead.

- **A seam clause that always fails still cost a frame, once per space
  operation.** The Node bridge's `seam:foreign_space/1` clause was consulted by
  the matcher, the type resolvers, the translator and the codec on every space
  operation, and cost one inference each time whether or not any provider
  existed. Measured by bisecting `bridge.pl` section by section against the
  seat's own `define-call` benchmark: 239,005 inferences with the clause
  against 238,505 without it, exactly one per call. The bridge carries no
  clause now and asserts the space NAME on registration, so a program with no
  provider pays nothing; `host-op` and `query-rows` improved with it
  [tested: sh extensions/node/bench.sh].

- **Five engine sources read as mojibake under a C locale, and one of them is
  the engine's own test-verdict mark.** `engine/qlf_boot.pl` forces UTF-8 for a
  boot that goes through `engine/main.pl`, and two files already declared their
  own encoding, but a direct `swipl engine/metta.pl` never reaches that
  forcing, and that is the boot every perf-measured child performs, because
  `measure_instructions` builds its environment from a small allowlist carrying
  no locale. The cost is not the warning. Measured on a minimal pair, the same
  file with and without the declaration: `atom_length('✅', L)` answers **1**
  with it and **3** without, so `runtime.pl`'s
  `test(A,B,true) :- (A =@= B -> E = '✅' ; E = '❌')` built a three-character
  mojibake atom instead of the mark it names. `:- encoding(utf8).` now leads
  `engine/metta/runtime.pl`, `engine/metta/space_hooks.pl`,
  `engine/filereader/source_lifecycle.pl`,
  `engine/translator/special_forms.pl` and `lib/lib_import/lib_import.pl`,
  ahead of every non-ASCII byte rather than merely near the top: SWI decodes
  the file as a stream, so a declaration placed after the first such byte is
  already too late, which is what the first attempt got wrong when the ω in
  `space_hooks.pl`'s header comment kept warning from line 42.

- **Four readers modelled "the gate" as one file, so each stopped seeing its
  own subject the moment a lane moved out of that file.**
  `tests/checks/evidence_runners.py` pinned its pytest collector to
  `check.sh`, so relocating that one lane dropped all 202 pytest files out of
  the executed model and turned 1,080 backed evidence claims unbacked in a
  single step: 575 executed files before, 373 with the field stale.
  `check_evidence_tags.gate_lanes` read the root file alone, so the
  `sh check.sh mypy ty` citation in `metta/_rules.py` was reported as naming a
  lane the gate does not run. `check_imports_selftest` asserted its command
  appears in `check.sh`, which reads a lane RELOCATION as command drift. And
  `test_packaging`'s `python -m` entry-point scan fell from 18 targets to 1
  and went on passing, which is the shape of a check that can no longer fail.
  `evidence_runners.gate_scripts()` is the single answer to which files are
  the gate now, and the three repository-root checkers read it. All three were
  ALREADY blind to `node-binding` and `c-binding`, because those components
  took their own lanes first: 52 lanes were visible reading `check.sh` alone,
  against the gate's 82. Both selftest fixtures build a component `check.sh`
  of their own now, so the split is the shape they prove against rather than
  one they happen to avoid.

- **The gate tested artefacts it had not built, so a verdict depended on how
  recently someone had built by hand.** `check.sh` built exactly two things
  before its lanes, the engine's C units and the chapter 19 examples, and named
  both by path. Every other component's artefacts were whatever was lying
  around: the Node seat's TypeScript is compiled by `npm ci` through the
  package's `prepare` script and by `extensions/node/build.sh`, and NO lane runs
  either, so after the petta-to-metta rename the `pytest` lane near the top of
  the file ran the OLD compiled bridge against the NEW `bridge.pl` and failed,
  while the `build` lane 160 lines below rebuilt it, which is why the next run
  passed with nothing changed. The pre-lane block is the same discovery
  `build.sh` uses now, in the same order, so every component is current before
  any lane reads it. Provisioning is deliberately not run there, because it
  clones two pinned dependencies when they are absent and a gate that reaches
  the network fails for reasons that are not the tree. Each build's output is
  captured and printed only on failure: a successful cargo build alone emits
  7,457 lines of warnings about a vendored dependency, and burying the lane list
  under them would trade one silent failure for another.

- **`bench.sh` is the benchmark suite now, and `metta bench` runs it.** The name
  belonged to the upstream comparison, which runs the shared example corpus
  against a Git base ref on both engines and answers a different question: is
  this revision slower than that one. What was missing is the question a
  baseline answers, is this case slower than its pin, and there was nowhere for
  a component's own suite to live. Root `bench.sh` discovers `engine/bench.sh`
  and `extensions/<seat>/bench.sh` the same way `build.sh` and `check.sh`
  discover their component scripts, runs every suite even after one fails so a
  run says how many regressed rather than stopping at the first, and passes its
  arguments through so `--update-baseline` reaches each component's own updater.
  The upstream comparison keeps its behaviour and its diagnostics under the name
  that says what it does, `tests/upstream_bench.sh`.

- **The `codespell` lane reads the Node and C seats, which it never did.** Its
  path list was written when those two folders were `bindings/` and never
  followed them, so two seats' sources and both their READMEs were the only
  shipped text nothing spell-checked. Widening it found three words, all of them
  deliberate and now named in `.codespellrc` with their reasons: `ans`, the Node
  seat's own name for an `Answers` handle across twelve call sites; `asSync`,
  the sync counterpart of `asAsync` where one pair reads `Symbol.iterator` and
  `Symbol.asyncIterator` off the same holder; and `derails`, which is the word,
  used correctly.

- **Python outside the Python seat is linted, which nothing did.** Every lint
  lane runs with `extensions/python` as its root, so the benchmark drivers the
  other components grew shipped with no linter reaching them: `engine/bench.py`,
  `extensions/node/benchmarks/` and `extensions/cmetta/benchmarks/`. The new
  `ruff-drivers` lane found eight real findings across three files, among them
  an exception class with no `Error` suffix and five `noqa` directives naming
  rules this configuration does not enable. It asks `git ls-files` what to lint
  rather than walking the tree, because a walk finds vendored build output
  nothing here owns: `extensions/mork/mork_ffi/target/` alone carries a
  generated jemalloc script with five findings, and what the repository TRACKS
  is the answer to what it is responsible for. The engine's benchmark driver is
  in the evidence gate's source list too, where `engine/*.py` had been missing
  beside `engine/*.pl`; adding it exposed one unbacked claim immediately.

- **The Python seat carries `test.sh` and `bench.sh`, so every component runs
  its own tests and benchmarks the way the gate does.** The Node and C seats
  gained both this session and the Python seat, which owns 206 test files and
  every committed counter baseline, had neither: its parallel configuration
  lived in the lane alone, so a developer typing `pytest` by hand got different
  settings from the ones that make the run correct, and `sh bench.sh` reached
  every suite except the largest. A new check names that class of gap rather
  than leaving it to be noticed: a component owning a test directory must ship
  the script that runs it, and one shipping a benchmark suite must ship the
  baseline it is measured against
  [tested: test_a_component_that_owns_tests_ships_the_script_that_runs_them,
  test_a_component_that_ships_a_benchmark_suite_ships_its_baseline]. It found
  the Python seat on its first run.

- **The engine carries `test.sh`, the last empty cell in the contract.** The
  plunit lane's body moved into it whole, which matters because that body is
  where the run's trustworthiness lives: the redirect that keeps swipl's exit
  status out of a pipeline, the working directory the suites' relative paths
  resolve against, the choicepoint scan, and the load-time error scan that
  catches a test which never ran at all. A developer had none of that, and the
  documented way to run one suite by hand still does not. The collector follows
  the loop, which also ends an ambiguity the engine-lane move reported: the
  anchor used to match twice inside `check.sh`, so removing either loop alone
  went undetected.

- `metta list` shows TEST and BENCH beside BUILD and CHECK. A component that
  has tests or benchmarks but no script to run them keeps them reachable only
  by whoever knows the path, and the four columns are what make that gap
  visible instead of inferred.

- **The evidence gate sees a component's `test.sh` and `bench.sh`, and every
  suite an npm script runs rather than the first one alphabetically.**
  `tests/checks/evidence_runners.py` discovered each component's `check.sh` but
  not the scripts that check.sh calls, so moving the Node seat's npm invocation
  into `test.sh` would have dropped all ten `extensions/node/test/*.test.ts`
  out of the executed model and left every evidence claim naming one of them
  unbacked. A runner's own directory is a candidate base now, which is what
  lets a component script's `cd "$HERE"` resolve to its own folder instead of
  to the root the root gate's `$HERE` means. Separately, the npm-script block
  added on 2026-08-27 landed directly above an existing `break` and captured
  it, so it recorded one suite and stopped: the model held `atom.test.ts` alone
  and holds all eleven now. `tests/checks/check_evidence_tags.py` reads every
  seat's benchmark baseline for commit pins rather than only the Python seat's,
  so a seat that grows its own benchmarks does not grow unchecked provenance
  [tested: sh check.sh evidence].

- **`extensions/mork/extension.pl` declares BOTH shared objects, so a
  half-built tree stops reporting a backend that is not there.**
  `morkspaces.pl` opens `libmork_ffi.so` for its global symbols and then loads
  `morklib.so` for `mork/3` itself, and it throws when either is missing. SWI
  prints a load-time directive that throws and carries on consulting, though,
  so `ensure_loaded/1` still succeeded and the loader still recorded the seat
  LOADED. A tree carrying only the declared artefact therefore answered every
  call with `Unknown procedure: mork/3`, on every boot, quietly; twelve of the
  seat's own tests raise there and twelve pass. With both declared it answers
  exactly as an unbuilt tree does, and `tests/mork_seat.plt` carries the
  invariant under it, unconditioned: a seat on the record has a working backend
  behind it.

- **`new-mork-space` is gone from the three tables that vouched for it,
  because it never existed.** It was registered as a `writesState` semantic
  effect, a grounded token, and a translator embedded-operation head -- a
  reviewed, typed, compiler-known operation -- with no implementation anywhere
  in the tree, so `(new-mork-space &z)` echoed itself while the effect table
  claimed a reviewed writer. It is declaration drift: named MORK stores are
  created on FIRST USE of `&mork:<name>` by design (the spaces guide records
  the contract), so the creation form it anticipated was obsoleted before it
  was built. The effects suite's reviewed profile is updated in the same
  change, which is that pairing's drift gate doing its job -- it refused the
  removal until the review record moved with it.
- **A worktree provisions every engine C artefact, not the reader by name.**
  `worktree.sh` compiled `engine/reader.c` and nothing else, so the day the
  engine gained a second C unit a worktree set up with it would have run that
  unit's Prolog fallback while its counters were compared against pins
  measured in C: `json-wire` reads 178,013 inferences with
  `engine/json_codec.so` and 169,336,779 without. It runs `engine/build.sh`
  now, which discovers what is beside it, and
  `tests/shell/test_worktree_configuration.sh` checks the property rather
  than a file name, so a third artefact is covered without another edit.

- **A JSON document with a key named `py` lost that key.** The network
  decoder passed `tag(py)` to `json_read_dict/3` under a comment saying it made
  read dicts cross janus the way written ones arrive. `tag/1` does not do that.
  It names the object KEY whose value becomes the decoded dict's tag, and that
  pair is then REMOVED: `{"py": "x", "a": 1}` decoded to `{'a': 1}`, silently,
  in both directions of a round trip. Nothing needed the option -- an ordinary
  object has no such key, so the tag stayed unbound either way, and janus makes
  a Python dict of a tagged and an untagged dict alike, measured both ways. The
  option is gone and the key survives.

- **The `json-wire` benchmark's wall figure was the removed `orjson` path's.**
  It read 7.741356699261814e-05 seconds a round trip, 77.4 microseconds, which
  is what `orjson` cost; the engine codec that replaced it on 2026-08-17 costs
  2,811.68, so the advisory number sat 36x adrift while the counters beside it
  were re-pinned four times. Re-measured with the rest.

- **`lib_json` encoded a document over many lines.** `json-encode` used
  `atom_json_term/3` with library(json)'s default `width(72)`, which switches
  to a vertical layout once a value passes 72 columns: the shipped `json-wire`
  payload came back as 32,643 characters of tab-indented text where the
  document itself is 25,017. It answers one line now, the same text the network
  codec produces for the same value, and anything already inside 72 columns is
  unchanged because library(json) was already laying those out horizontally.

- **`json-decode` ignored whatever followed the document.** `(json-decode "1 2")`
  answered 1. The network codec has always refused a second value in one text;
  both go through the same door now, so both refuse it.

- **A seatless engine crashed asking a question no seat was there to answer.**
  `engine/metta/space_hooks.pl` forwards two questions to a host -- is this
  error your transport dying, and how does your exception render as a MeTTa
  `(Error ...)` reason -- through hooks that only the Python bridge declared
  `multifile`, under the old `metta_host_` spelling. In every process without
  that seat, the WebAssembly host and the pure kernel included, the calls
  raised `existence_error` where "no" was the answer. Both hooks are seam-module
  seams now, `seam:host_transport_failure/1` and `seam:host_error_reason/2`,
  declared by the ENGINE (the caller) in `engine/ext_points.pl` with their
  `kind(_, ownership)` rows, and the old spellings are gone rather than
  aliased -- the seam-module suite's own doctrine, which rejected a first
  version of this fix that declared them user-module with the abolished
  prefix. A hook with no clauses now fails cleanly into the message-system
  rendering. The `prolog` lane runs TOKENLESS again as the regression gate:
  it is the one lane that checks the pure kernel, it is what exposed this,
  and the token it was given as a workaround would have hidden the next one.
- The reduced-platform child's withhold reached the LOADER only. SWI's autoload
  index is a cache of absolute paths, built on the first autoloaded call and
  re-read at most once a minute, and the child's own `member/2` builds it
  before the search paths are repointed. So a withheld library stayed callable
  through the cached path while `use_module/1` could no longer find it, and the
  child boot file's guarantee that `call_with_time_limit/2` is undefined there
  was false: with pcre and zlib withheld, `call_with_time_limit/2` and
  `concurrent_and/2` both resolved and `re_compile/3` ran. The child drops the
  three cached facts after repointing, so the next autoload rebuilds the index
  from the farms and the absence is real at call time as well as at load time.

- **The Node binding mounts each backend's control file rather than the whole
  `backends/` tree, so a built checkout can boot it.** `boot()` copied every
  directory in `ENGINE_DIRS` into the WebAssembly image recursively, and
  `backends/` holds the MORK crate, whose Rust `target/` is 10,808 files and
  3.2 GiB once `sh build.sh` has run. The image cannot hold that: the suite
  reported 70 tests with 8 test files aborting on `FATAL ERROR: ... JavaScript
  heap out of memory`, against 203 tests all passing with `target/` moved
  aside, same commit both ways (measured 2026-08-28 at e80fd4c3). So the lane
  was green only on a checkout that had never been built, which is the
  configuration nobody ships. `mountControlFiles` writes
  `backends/*/extension.pl` and nothing else, which is all the engine ever
  opens there: a wasm build has no dynamic linking and no janus, so every
  seat's needs are unmet and no `entry(engine, _)` is reachable. 203/203 with
  `target/` present.
- **`static_checks.pl`'s live-hook plant is removed by clause reference, so it
  stops surviving the run that planted it.** The check plants two cut-bearing
  clauses of `seam:function_removed/1` and one storage-registry row, proves the
  scan sees them, and removes them in a cleanup conjunction led by
  `retract((Module:Planted :- (!, fail)))`. That retract could never match.
  `assertz/1` qualifies the body of a clause whose head resolves to another
  module with the CALLING context, so the clause is stored as `user:(!,fail)`,
  and `setup_call_cleanup/3` ignores a cleanup that fails, so the conjunction
  stopped at its first goal. Every run therefore left both planted cuts live on
  a seam whose kind says every clause runs, and a space named
  `$static-check-fixture:&hook-probe` in the storage registry, for the whole of
  the rest of that run. Both are taken by the reference `assertz/2` returns now.
  The same measurement corrects what the pair proves: both clauses land in
  module `seam`, because the planted head is already module-qualified and SWI
  resolves `M1:(M2:Head)` to `M2`, so the pair is two clause references
  `distinct/2` has to keep apart rather than two modules holding a clause each.
  The module-agnostic discovery half is unchanged, since the walk still has to
  find the runtime-created execution module to reach them
  [measured 2026-08-28: after both asserts, module `seam` holds
  `[true, user:(!,fail), user:(!,fail)]` and each execution module holds none].
  Found by the new registered-space-name scan, which reported the leaked
  fixture as a space registered without the `&` prefix.

- **A seat declares itself in a control file the engine reads, instead of a
  decider script the engine runs.** Every folder under `bindings/` and
  `backends/` used to carry a `decider.pl`, twelve lines of imperative Prolog
  whose whole body was one hand-rolled `exists_file -> ensure_loaded ; true`.
  Each carries an `extension.pl` now: facts only -- `title/1`, `needs/1`
  (`artefact`, `prolog_library`, `predicate`, `extension`), `entry/2` keyed by
  who loads it (`engine` or `host`) -- READ with `read_term/3` and never
  consulted, which is PostgreSQL's control-file model and the one the runtime
  import scan already follows in those words (`engine/metta/interop.pl`). A
  fact outside the vocabulary refuses loudly naming the file and the term,
  proven by a planted directive that is refused and does not run.

  What this buys over the deciders: an unmet prerequisite is a queryable
  record (`metta_extension_unmet/2`) with the need named, instead of a silent
  `; true` branch -- the C seat on a non-C boot now reads
  `cmetta: predicate($cmetta_present/0)` where before it read as nothing at all;
  the Node seat, which had NO decider because its host consults the transport
  itself, gets a first-class identity through `entry(host, ...)` without the
  engine ever loading it; and the `entry/2` roles dissolve the seat naming
  split where `bridge.pl` meant the engine-loaded file in the Python seat and
  the host-consulted file in the Node and C seats. Boot behaviour is
  byte-identical: the same seats load under the same conditions, verified by
  the full pytest lane (2605 passed), plunit, the packaged wheel installed
  into a fresh venv, the worktree comparison, and a new
  `suites/seams/extensions.plt` covering the reader's refusal, every unmet-need
  kind, entry loading, host-entry exclusion, and the dependency need.

- **A host binding missing from `host_transport/2` is refused by name instead
  of passing by absence.** The published-surface walk read a hand-written list
  of three rows, and a seat left off it was silently unchecked -- the gate
  reported "every one of 2 host bindings" before the third was added, and meant
  it. The rows themselves cannot be derived: the Python seat's transport is
  `metta/shim.pl` where the Node and C seats' is `bridge.pl`, and "declares
  seam clauses" does not discriminate either, because `bindings/python/bridge.pl`
  declares eleven without being the transport. So the list stays, and the check
  now refuses any `bindings/*` directory with no row, naming it and what goes
  unchecked. Proven two-sided: a planted fourth seat directory fails the check
  by name and its removal restores the pass.

- **`check.sh` discovers each component's lanes instead of listing them, and
  one `metta` CLI replaces five root scripts.** The gate named
  `bindings/node`'s lane and `bindings/cmetta`'s lane in its own body, which is
  the defect `ai-cmetta-c-constraints.md` C4 filed as "a new seat is three
  registrations, not one folder". Those lanes live in
  `bindings/node/check.sh` and `bindings/cmetta/check.sh` now, and the gate
  SOURCES every `engine/check.sh`, `backends/*/check.sh` and
  `bindings/*/check.sh` it finds.

  Sourced rather than executed, deliberately: executing them would make each
  component report its own status, and a driver that loses a child's exit code
  is exactly how a red lane reads green. Sourcing keeps one `run`, one summary
  table and one exit status.

  That move had a trap under it. `tests/checks/evidence_runners.py` models which
  files a lane executes by READING the gate's text, from a hardcoded tuple of
  four scripts, so a lane that leaves `check.sh` leaves that model too and its
  files read as unrun. The tuple discovers component scripts now. Measured: it
  restores exactly one file, `bindings/node/test/atom.test.ts`, and no evidence
  tag cites that file today -- so this closes a latent gap as component lanes
  grow rather than repairing a live break.

  `./metta` carries the verbs: `build`, `check`, `test`, `run`, `bench` and
  `list`. Each delegates to the script that already existed, which stays
  runnable on its own because CI and the documentation invoke them directly.
  `list` is the one that pays for itself -- it reports every component, which
  contract files it carries, and whether it can build HERE with the missing
  prerequisite named -- and it builds nothing to answer, verified by deleting
  `engine/reader.so` and confirming `list` leaves it deleted.

- **Every component now ignores its own build products and builds itself.**
  The root `.gitignore` carried six blocks naming paths in other components --
  the chapter 19 objects, `engine/reader.so`, five `bindings/cmetta` products,
  `bindings/python/metta/*.so`, `bindings/node/node_modules/` and `*.qlf` --
  so a rule lived four directories from the thing it described. Five new
  per-component files (`engine/`, `lib/`, `bindings/cmetta/`,
  `bindings/python/`, `examples/ch19-*/`) join the two that already existed,
  and the root file keeps only repository-wide rules with a header saying so.
  Verified with `git check-ignore -v` over 17 products: every one resolves to
  its own component's file, and the repository-wide ones to the root.

  `check.sh` also stopped being the build system. It compiled the chapter 19 C
  examples and `engine/reader.so` inline, at script top level, which made a
  script named for checking the only way to produce two artifacts. Both moved
  into `engine/build.sh` and `examples/ch19-*/build.sh`, joined by
  `backends/mork/build.sh`, `bindings/cmetta/build.sh` and
  `bindings/node/build.sh`, and the root `build.sh` DISCOVERS them by glob
  rather than naming one: a new component is a directory with a `build.sh`,
  which is the rule the engine already applies to a decider. Each script draws
  the deciders' split -- an ABSENT toolchain exits 0 with a note, an ATTEMPTED
  build that FAILS exits nonzero -- and the driver collects failures and names
  them, so no script has to report success it did not earn.

- **The reduced-platform harness could only withhold a library from two
  directories, and silently ignored any other.** `tests/prolog/reduced_platform.pl`
  builds a real SWI minus chosen libraries by mirroring directories with
  symlinks, and it named exactly two: the main library and `clib`. The child
  then re-added every OTHER real directory to both search-path aliases. SWI
  keeps its libraries in several (`pcre` in `library/ext/pcre`, `zlib` in
  `library/ext/zlib`, `clpfd` in `library/clp`), so a withhold aimed at any of
  those did nothing at all and the child resolved the library from the real
  installation. Measured: withholding `pcre.pl` produced a clean boot that
  would have read as evidence the engine survives without it.

  The directories are derived from the withheld libraries now, the parent
  writes the farms it actually built to a manifest the child reads (the child
  cannot derive them: resolving `library(thread)` is the very thing it must not
  be able to do), and cleanup enumerates what was created rather than what was
  expected. Three hardcoded copies of the same pair are gone. Withholding
  `pcre` now does what it says: the child reports
  `source_sink 'library(pcre)' does not exist` at `engine/metta.pl:481`, which
  is the capability gap the census exists to name and does not yet cover.

- **`checks` repeated six of `test`'s pins instead of saying it contains them.**
  The two extras overlapped exactly -- `hypothesis`, `networkx`, `numpy`,
  `pytest`, `pytest-benchmark`, `pytest-xdist`, identically pinned in both --
  and keeping them equal was a hand job with nothing checking it. `checks` is
  `["pymetta[test]", ...]` now, the PEP 508 self-reference that exists for this,
  and the six duplicates are gone. Measured: `uv lock` resolves the same 86
  packages, `uv sync --locked --extra checks` still installs all six through the
  reference, and the lockfile's own record collapses six `extra == 'checks'`
  rows into one `pymetta[test]`. `test_optional_integrations_have_installable_extras`
  asserts the RESOLVED sets now rather than the literal spellings, including the
  superset relation itself, which is stronger than the six membership pairs it
  replaced: those could all hold while a seventh pin drifted, and this cannot.

- **`docstring-parser` was capped below the current release for no recorded
  reason.** `>=0.17,<0.18` arrived with the typed-documentation work
  (`bd23e0ee`) carrying no rationale, and 0.18.0 is now the latest release, so
  the cap was handing users a resolver conflict. Measured rather than assumed:
  the two names this library uses, `DocstringStyle` and `parse`, are present in
  0.18.0 and parse identically, and the whole pytest gate passes against it.
  The bound is gone; the lockfile still resolves 0.17.0, so what ships is
  unchanged and what a user may install is no longer needlessly narrowed.
  `janus-swi` has never carried an upper bound and this now matches it.

- **`bindings/cmetta` declared its build inputs in prose, and prose cannot
  refuse.** The Makefile header named swipl, `libswipl` and a C11 compiler in
  three sentences nothing read, so a tree without SWI's development files got
  `PLBASE=""`, compiled against `-I/include`, and failed on a missing
  `SWI-Prolog.h` with the true cause named nowhere. The three prerequisites are
  checked now and each refuses by name with the package that supplies it.
  `clean` is exempt, because removing build products needs no toolchain and a
  machine that cannot build this should still be able to tidy up after one that
  could.

- **The engine classified a host's builtins by naming them, which is the one
  thing `EXTENDING.md` promises an extension author never has to force.**
  `seam:host_builtin/1` and `seam:backend_builtin/2` were one concept under two
  names, and the ARITY was the damage: `metta_builtin_effect/2` reads a
  builtin's effect class from that seam, so a backend could declare one and a
  host had nowhere to put one. The seven `py-*` builtins were therefore
  classified by a list of their names inside `engine/metta/effects.pl` --
  `metta_builtin_effect_override('py-list', oracleIO)` and six siblings -- which
  is exactly the shape MORK stopped needing when `backend_builtin/2` grew its
  second argument, and exactly what `host_builtin/1`'s own comment said did not
  exist ("no list inside the engine names a host").

  Both seams are now `seam:extension_builtin/2`, declared by hosts and backends
  alike, and the seven rows are gone from the engine. The classifications
  themselves do not change -- all seven stay `oracleIO`, which is honest,
  because each crosses into a Python runtime the engine cannot bound, and
  `py-list`/`py-tuple`/`py-dict` only look structural: they build a live object
  whose IDENTITY is observable, so two calls with equal arguments answer
  distinct objects. What changes is that the review lives with the code it
  reviews, and a second host binding gets the same door instead of an engine
  edit.

- **The guard for that property existed and two scope filters hid the
  violation.** `test_no_code_in_the_engine_names_a_host` globbed `engine/*.pl`,
  one level, while the engine's code also lives in `engine/metta/`,
  `engine/spaces/`, `engine/translator/` and `engine/filereader/`: 18 files
  scanned of 40. Its token pattern was `\bpy_|\bpython|\bjanus`, which cannot
  match `'py-list'`, because MeTTa spells names with hyphens and Prolog does
  not. Both filters were load-bearing and the defect needed both to survive.
  Measured against the tree before the fix: 7 offenders with the scan root and
  the pattern corrected, 0 with either left as it was. The scan is now
  recursive and includes `py-`, which is what makes the property checkable
  rather than merely stated.

- **`git-import!` answered two different values depending on how many arguments
  it was given.** Its three unpinned clauses answer `[]`, the unit every
  effectful builtin in this engine answers -- `'import!'/3`, `'println!'/2` --
  and the pinned five-argument clause alone answered `true`. So one program
  importing a pinned dependency and then a library printed `True` for the first
  and `()` for the second, and a caller passing the unit explicitly did not
  match the head at all: it FAILED, with no error, because a failed goal is not
  an error. The pinned clause now answers `[]` like its siblings, and
  `tests/shell/test_git_import.sh` checks all four arities answer the same unit,
  so the four cannot drift apart again.

- **Three shell suites existed that nothing ran, and two had rotted.** `check.sh`
  named 6 of the 10 scripts in `tests/shell/`; the rest were reachable only from
  `.github/workflows/ci.yml`, which gates pull requests into `main` and
  therefore never sees branch work. Measured on a clean control worktree at
  `91e339cb`, so neither failure is caused by the build work beside it:
  `test_loader_concurrency.sh` asserted into `translator_rule/1` after that
  became a STATIC projection over the dynamic `translator_rule/2`
  (`translator_rules.pl:173`), raising "No permission to modify static
  procedure"; and `test_git_import.sh` passed a literal `true` in the MeTTa
  result slot, which is the defect above. Both are fixed -- the first registers
  through `translator_rule/2` with `[]` for "declared nothing", the second
  passes the result slot UNBOUND, which is what a real caller does and what
  keeps a suite from encoding a convention it is not about -- and all three are
  now GATE lanes (`git-dependency`, `git-import`, `loader-threads`). Each
  assertion in the concurrency suite was proved to still discriminate by
  perturbing its expected context and watching its own distinct error appear.

- **The MORK shim is built with `swipl-ld`, removing the tree's only
  `pkg-config` dependency.** `morklib.so` is loaded with `use_foreign_library/1`
  (`morkspaces.pl:323`), so it is an extension loaded INTO SWI -- the same thing
  `engine/reader.so` and the chapter 19 C examples are, and all of those already
  build with `swipl-ld`, which ships with SWI-Prolog and is therefore present
  wherever the engine is. Only this one script asked `pkg-config`, and not every
  SWI build installs `swipl.pc`: where it is absent
  `$(pkg-config --cflags --libs swipl)` expanded to nothing and `gcc` failed on
  a missing `SWI-Prolog.h`, blaming the wrong thing.

  `bindings/cmetta` deliberately keeps `swipl --dump-runtime-variables`. It calls
  `PL_initialise` (`cmetta.c:1353`) and so EMBEDS SWI in a C program, the opposite
  direction, which `swipl-ld` does not build. The two mechanisms are not
  duplicates of each other; `pkg-config` was the only redundant one.

  Measured 2026-08-28: both spellings produce a 15768-byte object exporting the
  same ten symbols and the same install hook. The engine loads the rebuilt shim,
  `seam:foreign_space('&mork')` answers, the 26 MORK tests pass, and `lib_mm2`
  stores and queries atoms through it end to end.

- **`build.sh` reported success it had not earned, and dirtied the tree doing
  it.** Four defects, all in 27 lines. It had no `set -e`, so a failed
  `cargo build` fell through to the next line and the run still ended by
  printing `Successfully built mork_ffi` -- that message was unconditional, and
  the `nm -D … | grep rust_mork` above it decided nothing because its exit
  status was discarded. It resolved `../MORK` and `cd ./backends/…` against the
  CALLER's working directory, so `sh /path/to/PeTTa/build.sh` provisioned beside
  the caller instead of beside the checkout, where `run.sh` has anchored itself
  with `SCRIPT_DIR` all along. It cloned the pinned siblings only when the
  directory was ABSENT, so a MORK left on another revision was taken as correct
  and produced an artefact built against an unvalidated tree with nothing said;
  the revision is now checked on every run and a mismatch prints the `git -C …
  checkout` line that restores it. And its last four lines cloned `faiss_ffi`
  with no destination argument after two `cd`s, which landed a whole vendored
  checkout in `backends/mork/faiss_ffi`, a path no ignore rule covers: one
  successful run dirtied `git status` and the next failed on "destination path
  already exists".

  That faiss step is gone rather than repointed. `faiss_ffi` is a third-party
  MeTTa library, not a backend in this tree, and the engine already fetches it
  at a pinned revision through its own package manager --
  `!(git-import! "https://github.com/patham9/faiss_ffi" "build.sh")`, which is
  what `examples/ch20-extending-the-engine/20-04-modules-and-the-catalog/07-git_import2.metta`
  demonstrates and what put `repos/faiss_ffi` there. `README.md` and
  `tests/prolog/README.md` said the script builds FAISS; they now say what it
  does. Toolchain checks moved to the backend's own script, which names every
  missing prerequisite at once instead of failing inside a compiler, and says by
  name when `pkg-config` cannot answer for swipl rather than letting
  `$(pkg-config …)` expand to nothing and blaming a missing `SWI-Prolog.h`.

  `tests/shell/test_build_is_idempotent_and_anchored.sh` is the new GATE lane
  behind all of it: two runs from a directory that is not the repository root,
  both exit 0, `git status --porcelain` byte-identical, no
  `backends/mork/faiss_ffi`, and the backend script exiting nonzero while naming
  what it could not find when run with no toolchain on `PATH`. Each assertion
  was proved to discriminate by planting the defect it exists for. It skips
  rather than clones when the siblings or the build are absent, so it never
  reaches the network [measured 2026-08-28: 5.0s against a warm build].

- Two gate lanes were failing on a path rather than on what they check, both
  left behind when the plunit suites were grouped. `check.sh`'s ciao-grade lane
  ran `ciao_grade.plt` from `tests/prolog`, where the file is
  `suites/seams/ciao_grade.plt`, so SWI reported a missing file. The
  spec-status selftest ran its copy of the checker from `<tree>/tools/` while
  the real file sits one directory deeper, so the copy read the wrong root and
  could not find the fixture's spec; the same fixture also still spelled its
  plunit lane `for suite in *.plt`, which the runner model no longer matches by
  anchor, so the fixture's own planted FIXED case read OPEN. Every runner was
  then swept for the same class, and none names a path that does not exist.

- The notebook lane reads either shape of a stored `text/html` output. It
  compared the marker against whatever the JSON held, and nbformat stores a
  multiline string as a LIST of lines, so the check passed only while the
  shipped notebook happened to have been written by something that was not
  nbformat. Saving the tour once from Jupyter would have turned the lane red
  with nothing wrong.

- A proof tree no longer reports the engine counting its own recursion. Every
  recursive equation compiles with a stack-depth charge in front of its body,
  and the proof-tree meta-interpreter walked that charge as if it were part of
  the program, so each recursive step read `builtin
  system:b_getval('$metta_fuel_remaining',off)` and `builtin off==off` before
  its real premises. In the notebook tour's own ancestor proof that was three
  lines of engine plumbing against five of program. The charge still RUNS,
  where the body would have run it, and contributes no node.
  Recognising it is the engine's job, published as `metta_host_stack_charge/3`
  beside the generator that writes the charge, because every binding that walks
  compiled clauses meets it and a shape each of them spells again drifts the
  moment the charge changes. It matches the charge's first conjunct against
  that generator and ties the branch beside it to the read by variable
  identity, since `clause/2` decompiles and `Remaining is Limit - 2` reads back
  as `Remaining is Limit + -2`.

- `m.trace` takes the term every other door takes. `m.answers`, `m.eval`,
  `m.match`, `m.cast` and `m.derivation` all take a built term, and trace took
  only text, so the one door that exists to SHOW you a reduction was the one
  door that made you write the program a second time as a string.
  `m.trace(S.fib(10))` now reads like the rest of the surface. The tracer runs
  source, so a term is written with the surface's own writer and prefixed with
  the `!` that makes it runnable; a string is passed through untouched, `!`
  included or not, so every call written before this means what it meant.

- An evaluation answer no longer renders as a row of bindings. `Answers`
  carries two faces, the values a call answered and the caller bindings behind
  them, and its eager table doors reached the second by asserting that the
  first was already a row. The assertion was a `cast`, which does nothing at
  runtime, so an ATOM arrived at `Rows` and was taken apart by `tuple(atom)`:
  the single answer `(g $p)` to a two-variable call became two cells under the
  headers `x` and `y`, and `to_dicts()` read `{'x': 'g', 'y': '$p'}`, naming a
  head symbol as a binding. Answers whose arity did not line up raised instead,
  `to_dicts`, `table`, `build`, `to_df`, `to_pl` and `pipe` with a plain
  `ValueError` and both notebook and terminal renderers from inside the display
  machinery, so `m.answers(S.ancestor(S.Tom))` as a Jupyter cell's value was a
  traceback rather than three ancestors. The table doors now refuse term
  answers and name `.rows` as the door to the bindings, and the two display
  faces list the answers, bounded by `config.display_rows` and pulled only that
  far, so a cell holding an unbounded answer stream still renders.

- A compiled object is no longer committed. `cstore.so`, the C-space example's
  shared library, was tracked while its two siblings `cbump.so` and `handle.so`
  were gitignored build products, and while the README beside it tells a reader
  to compile it. It was tracked because nothing built it: `check.sh` named
  `cbump` and `handle` by hand. Both `check.sh` and `worktree.sh` build every
  `.c` under a chapter-19 section now, so a fourth needs no edit, and the fork's
  corpus manifest pins the third object's existence the way it pins the other
  two.
- Three commands in the tree told a reader to run pytest with
  `--rootdir=python`, the location the Python binding left in the P0.27
  partition. That directory exists in a working checkout only because those
  commands create it, holding nothing but tool caches, and
  `test_documentation.py` pinned the wrong one so the gate endorsed it. They
  name `bindings/python`, and the stale `python/` ignore rules go with it. The
  evidence gate's own `$PYDIR` substitution read `python/` for the same reason;
  no lane writes that shape today, so nothing had been lost yet.
- The evidence gate reads an interpreter-led gate command as a command. Its
  own scheme says a `tested` tag carries either a test name or an exact gate
  command, and it knew one spelling of the second, `sh check.sh <lane>`.
  `python bindings/python/tools/phrasebook.py --gate` was split into words
  instead, and the leading `python` was looked up as a test NAME. It resolved,
  because `python` was the stem of a shipped example, so two phrasebook claims
  were backed by an unrelated MeTTa program for as long as they had been
  written. The checker now recognises `python`, `swipl` or `node` followed by
  a script path, and asks the same question it asks of a lane name: does a
  GATE lane run it. `tests/check_evidence_selftest.py` plants both directions.
- The `encoding` gate lane runs again on a checkout that has built the MORK
  backend. It probes under a scratch copy of the tree, and the copy was
  `cp -a` of the whole checkout: 4.1 GiB here, of which 3.0 GiB is the MORK
  crate's Rust `target/` intermediates and 0.5 GiB is `.git`. Where `TMPDIR`
  is a tmpfs the copy ran out of space, and the lane reported "could not copy
  the tree to probe under", which reads as a broken test rather than as a
  full disk. It copies through `tar` now, excluding version control, tool
  caches and build intermediates, which is 37 MiB; every built backend
  library under `target/release` is kept, and the MORK backend still loads in
  the copy, because a probe that quietly loads one backend fewer would be
  probing a configuration nobody ships.
- The Node binding's own documentation said the number transport carries text
  "because the engine answers `False` to `(== 2 2.0)`". It answers **True**:
  numeric equality is by value across the integer/float constructors, following
  LeaTTa's `Ground.equiv`, as `engine/metta/operators.pl` states and an engine
  test already covers. The conclusion the documentation drew was right and only
  its evidence was wrong, so the reason is now the one that holds: 2 and 2.0 are
  different ATOMS, which `=alpha`, a `case` pattern and `subtraction-atom` each
  show, and identity is what a codec has to preserve.
- A failing MeTTa assertion no longer writes to the stdout of the process that
  embeds the engine. `assert/2` reported through a bare `format/2`, which goes
  to `current_output`, and for a host that embeds SWI in its own process that
  is the host's own stdout: an embedded caller could not suppress it, and
  redirecting output the host owns to hide it is worse than the problem. The
  print dates from upstream, where this predicate ended in `halt(1)` and the
  print was the only report there would ever be; the commit that made the
  failure a catchable exception left the print behind, and it has been a
  duplicate of the exception's own rendering since. It now goes through
  `print_message/2`, so it lands on `user_error`, renders through the one
  `prolog:error_message//1` clause the engine already had for that formal, and
  can be intercepted with `message_hook/3` by a host that wants only the
  exception. Reporting and then throwing is deliberate and is what SWI's own
  `assertion/1` does: a ball can be swallowed by any `catch/3` up the stack.
  `test/3`'s `is ..., should ...` line stays on stdout, because that one prints
  on success too and is a trace of a check that ran rather than a failure
  report; `test.sh` tells the failure shapes apart by exactly that difference,
  and `tests/test_example_runner_surfaces_failures.sh` now runs all three
  shapes through the runner and through a copy of it with the stdout+stderr
  capture removed, so what that capture buys is measured rather than described.

- Engine verbosity has a published door, `metta_host_set_silent/1`, so a host
  with no command line to read stops reaching into engine internals for it.
  `engine/filereader.pl` decides `silent/1` from `argv` at load time, which an
  embedded host has none of, and the Python and C seats had each written the
  same retract-then-assert under a private name while the engine's own export
  comment named the first of them. Both copies are gone, the engine's comment
  names the service instead, the service carries a `seam:kind/2` declaration
  like every other host-facing predicate, and it refuses a non-boolean before
  it retracts anything rather than leaving every reader on a value none of them
  match. `silent/1` now has one writer in the tree outside its own boot
  directive; the four Prolog gate harnesses and the one Python test that
  spelled the pair themselves go through the door too.
- An `inferences=` budget now bounds a lazy cursor. It did nothing: draining
  20,000 rows through `m.match()` or the cursor door under a budget of 5,000
  returned all 20,000 rows, and so did every larger budget.
  Two facts had been read backwards. An SWI engine has its OWN inference
  counter and the thread that created it cannot see that counter, so a bound
  placed around a pull charges the pull loop: 1,000 pulls of a goal costing
  about 402 inferences each moved the calling thread's counter by 2,003, 0.50%
  of the work. And `call_with_inference_limit/3` bounds inferences per SOLUTION
  of its goal, which is what SWI's manual says, so a generator answering cheaply
  forever is re-armed at every answer and never reaches it.
  The budget is now built by `metta_host_inference_budget/3`, which keeps that
  limiter, because it is the only bound that stops a resume which never yields
  an answer at all, and adds the engine's own counter read against a base taken
  when the goal starts. Spend is bounded by the budget plus one answer's cost,
  except where a single answer overruns the whole budget on its own, which can
  reach twice it. A cursor with no budget installs no wrapper and is unchanged;
  a bounded cursor costs two engine inferences per answer, and those are spent
  in the cursor's engine where no host-side counter sees them.
  `m.stats()` is the other side of that fact and it now says so: it reads the
  calling thread's counters, so it sees about 10.5% of what a lazy `match()`
  cursor's engine actually spends. The evaluation cursor behind `answers()`
  reports its engine's spend and is whole. Changing that for the match cursor
  would change the hot pull's wire and is not in this change.

- The C binding's cursor inference bound counts the engine's work. It metered
  with `statistics/2` either side of each `cmetta_answers_step()`, which reads
  the CALLING thread's counter, and a cursor's engine is not in it: at a budget
  of 20,000 that meter bought exactly 4,000 answers from a cheap generator and
  exactly 4,000 from one whose answers cost 137x more, the same count for both.
  It now builds the budget into the engine goal through
  `metta_host_inference_budget/3` and buys 1,233 and 9. The old meter, the
  per-cursor spend column and `petta_c_cursor_spent/2` are gone with it.
  A C caller also now gets `CMETTA_LIMIT` rather than `CMETTA_ERROR` when a MeTTa
  program spends its own `(pragma! max-inferences N)`, because the classifier
  reads the engine's reserved limit envelope as well as this binding's own.

- The engine's reserved limit envelope prints its bound instead of its term.
  A program that spent `(pragma! max-inferences 500)` reported
  `Unknown error term: metta_control_signal(inference_limit,500)` at the CLI and
  anywhere else message text is shown; it now reads "the evaluation passed its
  500 inference bound and was stopped". The wall-clock kind had the same gap and
  the same fix.
- The C binding no longer says MeTTa tells `2` from `2.0` through `==`. It
  does not: numeric equality is by VALUE across the integer and float
  constructors, following LeaTTa's `Ground.equiv`, so `(== 2 2.0)` answers
  True. What is true, and what the C seat's `CMETTA_INT`/`CMETTA_FLOAT` split
  actually rests on, is that `2` and `2.0` are two ATOMS: a stored `(f 2.0)`
  does not match the pattern `(f 2)`, and each prints as itself. `cmetta.h` and
  `bindings/cmetta/kit/corpus.json` carried the wrong half of that.

- `examples/reasoning/greedy_chess.metta` is skipped for the reason that is
  true. It read "long-running, covered by benchmarks" and neither half held:
  no benchmark in any baseline names it, and given its quit command it loads
  all 2,821 lines, sets up the board and exits 0 in about a quarter second.
  What it needs is a terminal. The file ends in `!(main_loop)`, whose
  `(command-loop)` reads with `readln!/1` and recurses on anything but `q`,
  and `read_line_to_string/2` answers `end_of_file` for every read once
  stdin is at EOF, so under a runner the loop never ends rather than running
  long: 17,973,938 lines in 120 seconds, one prompt and one refusal per
  cycle, where a complete run prints 16,123 and stops. Both halves are now
  checked, since a skip reason nothing checks is how the wrong one survived.
- The `json-wire` benchmark measures the engine work it has always paid.
  `metta/_json.py` is the engine's codec, so `dumps` and `loads` each reach
  `library(json)` through janus and one round trip is two crossings and two
  Prolog passes; the case registered `engine=None` anyway, which pinned the
  row at `"inferences": null` and made the comparator require it to stay
  null. The heaviest crossing in the roster was therefore gated on retired
  instructions alone, with 169,336,779 inferences a sample uncounted, more
  than any other row in the file. The row now carries that pin, measured at
  84,668 inferences a round trip and identical across three fresh
  processes, and the pin defends the wiring: registering the row engine-free
  again fails the lane instead of passing green.
- A benchmark row's declared instruction noise band survives a re-pin.
  `BenchmarkBaseline.observe_instructions` took the band as a defaulted
  parameter and wrote that default into the row on every `--update`, and
  `benchmarks/check_instructions.py` passes none, so each re-pin rewrote the
  1.0 default over whatever the row declared and left the comment beside it
  describing a band the gate did not carry. Both declared widenings had been
  reverted that way: typed-call's 5.0, raised for a code-layout swing
  measured at 3.13%, and json-wire's 2.5, widened for one measured at 1.56%.
  Each lane therefore stood gated inside its own measured noise, where it
  goes red for layout and is then re-pinned past a real regression. The
  count is measured and the band is declared, so an update now writes the
  count alone and fills an absent band once; both values are restored and
  neither pin moved.
- Loading the engine no longer lets SWI's `library(arithmetic)` judge a
  host's arithmetic at compile time. `engine/metta.pl` imports
  `library(listing)`, which loads `library(settings)`, which loads
  `library(arithmetic)`, whose `system:goal_expansion/2` hook is consulted
  for every module the process compiles and raises
  `type_error(evaluable, F)` at COMPILE time for an expression SWI itself
  compiles and raises on at run time -- and a raising expansion silently
  drops the whole clause in flight: `tests/prolog/metta.plt` registered 233
  tests instead of 234 in every configuration. The engine now repairs the
  hook rather than dodging the load: at boot it replaces the unguarded
  clause with one that defers an unknown evaluable to run time, and a
  `prolog_listen/2` watcher re-applies the guard the moment anything
  installs that clause again, a reload or a host loading
  `library(arithmetic)` itself, so every configuration ends in the same
  state. Declared `arithmetic_function/1` functions still expand and
  evaluate, and `tests/prolog/static_checks.pl` proves the class invariant
  against a planted throwing expander.
- The plunit gate reports a suite that fails to LOAD. `swipl -t halt` exits
  0 and `run_tests` only reports the tests that got registered, so a plunit
  test whose body failed to compile did not run, did not fail and did not
  appear in the count: `tests/prolog/metta.plt` reported 234 tests as 233
  with a green lane above it.
- The layering contract's subsystem attribution is deterministic again.
  Adding the tabling library as a second case made
  `contract_source_subsystem/2` two clauses over a variable first argument,
  so every engine file left the tabling clause behind as a choicepoint and
  `engine_goal/4` became nondeterministic; the two cases are exclusive and
  now say so.
- Planning a specialization no longer metacalls a lambda once for each
  position of a call argument. The plan grafts the call's argument onto a
  fresh copy of the equation's head pattern, and that walk carried its
  binding step as a yall lambda, so every position paid `'>>'/4`'s
  `copy_term_nat` and its rebuilt goal, and the first plan in a process paid
  the lambda machinery's one-time resolution on top. The
  writable-specialization merge made the source-pairing step fail earlier for
  functions whose retained clauses do not pair, which stopped the engine's own
  boot from reaching the walk and moved that one-time cost onto the first user
  equation that did: the first call of a defined function whose body holds
  `once(match(...))` read 3,676 inferences where it had read about 2,208. The
  walk is first-order now and costs 4.0 inferences per position against 17.0,
  the same 3.6-to-4.7 ratio `tests/prolog/static_checks.pl`'s
  `compile_time_helper('>>')` rule records for this defect in generated
  bodies. That first call reads 2,163 with later calls unchanged at 423, and
  the arrival cost of a match-bearing equation stays flat as the program
  grows: 2,215 with 10, 40, 160 and 640 other translated equations in the
  space. Across the 219 twinned examples, 64 run cheaper by 1,248 to 6,317
  inferences and none runs measurably dearer: adding an inert never-called
  clause of the same size to `engine/specializer.pl` moves the handful of
  small movements in either direction by more than the change does, so those
  are compiled-image placement, and the same inert clause leaves the
  first-call probe at 3,676 exactly. Sixty of those twin budgets are re-pinned
  here. Three of the remaining four read differently across two full-lane
  rounds on one tree, so a single measurement would be a coin toss and they
  want an empirical band; the fourth, `libraries/thread_linda`, already
  declares one instead of a pin. All four are left alone. The
  `let-heavy` counter row moves 16,015,029 to 16,014,990, three walked
  positions at 13 inferences each, and is left for the merge's own pricing
  pass over `bindings/python/benchmarks/baseline.json`. `metta_ensure_compiled/1`
  in the plan, the suspected cause, measures 6 inferences per call over the 95
  calls `examples/libraries/roman.metta` makes, and was not it.
- Asking a lazy answer view how many answers it has no longer costs what
  reading them costs. `space.answers(call, under=counting)` builds a view
  whose only source is the scalar, so its count is that view's whole
  evaluation and the effect-repeatability question cannot arise; it now asks
  the engine to count directly instead of taking the guarded door, which had
  been sending an effect-bearing goal through a materializing pass that
  encoded and crossed every answer to reach a number nobody kept. `len()` on
  a view that also holds a cursor keeps the guard, and when the goal is
  effect-unsafe the count and the values now come from ONE evaluation that
  holds its answers in the engine one step short of the wire: the length
  crosses one integer, a later value demand encodes only the answers it
  pulls, and the effects still fire exactly once, so `list()` cannot execute
  an effect for its length hint and again for its values. Crossing an answer
  costs 9.1 plus 8.0 per term node in engine inferences, measured over a
  depth sweep, and that product is what a discarded length used to pay. Four
  corpus twins are re-priced: `matespacefast` 324,566,172 to 74,483,636
  (-77.1%), `matespace` 116,492,911 to 32,668,415 (-71.9%), `matespace2`
  124,314,232 to 50,679,104 (-59.2%), and `peano` 2,396,435 to 2,033,218
  (-15.2%). A carrier cursor answers an annotation beside every value, which
  the holding evaluation does not carry, so its declined count still counts
  through one materializing pass.

  `list(view)` asks for an iterator before it asks for a length hint, so a
  count source is now told whether the values are already wanted. Holding
  answers to avoid a second evaluation buys nothing for a caller about to
  read them, so that caller keeps the one materializing pass it always had.
  The hint picks a route and never an answer: a Python that asked in the
  other order would pay the holding evaluation rather than answer
  differently.

- The tabling library rides the declared extension seams only, and its
  tables are visible wherever the answers are: a `(tabled ...)` declaration
  now tables `as shared` (checked native-space readers
  `as (incremental, shared)`), so a live Python `Answers` cursor, the
  source runner, and a later `(table-stats ...)` call all enter one answer
  trie instead of a cursor-engine-private one that read as zeros. Calls
  route through the same `dispatch_call` ownership seam the memo library
  uses, reflection writes are checked and refuse loudly as
  `metta_tabling_reflection_write_failed` with a rollback of the
  just-installed table, and the library's exact engine reaches are pinned
  in the layering contract. The statistics example counts two completed
  calls after one completion and one invalidation re-evaluation, where the
  old three included the extra private-engine path; the shared scope is
  what SWI charges for cross-engine visibility, priced on the tabling
  twins' budgets. EXTENDING.md walks the library as the proof that a
  tabling-grade extension needs no engine changes.

- The writable-specialization merge had resolved `benchmarks/baseline.json`
  to its branch's stale copy, reverting the typed-shadowing re-pins on
  twelve inference and three instruction rows and dropping their mechanism
  comments. The comments are restored verbatim from the typed-shadowing
  merge and every affected row is freshly measured and re-pinned; a stash
  A/B confirmed the open-tail indexing fix moves none of them. The whole
  twin corpus is re-priced in the same pass, with every movement beyond
  layout attributed at its exact commit pair: the relational-candidate rows
  (matespace-family and peano costs), the specialization merge's
  per-translated-equation bookkeeping (the once/cut/curry class and roman),
  the algebra-tower routing's unrecorded improvements (permutations,
  he_minimalmetta), and the recoveries from the open-tail index and the
  deprecation probe.

- The callable doors' deprecation check no longer compiles a fresh goal
  string per name: an empty catalog, the common case, is now one process-wide
  apply-seam probe. The per-name read had cost 1,311 inferences on the first
  call of each name (the parse twin read 391 before the deprecation catalog
  landed and 1,679 after; it reads 404 now), which had silently inflated
  nearly every twin budget. A deprecated name still warns with its
  since/remedy declaration; only the empty-catalog fast path changed.

- An open-tail, bound-head `get-atoms` pattern, the shape of the tabling
  library's `(tabled ...)` existence probe, now reads through the store's
  first-argument index per held arity instead of walking every stored atom,
  and an improper tail concludes a deterministic miss instead of a
  store-content-dependent `=../2` type error. The walk had made every
  definition-change hook pay the whole `&metta` catalog: 23.7 inferences per
  catalog row over one tabling_fib load, linear with planted rows (74,268
  inferences at +0 rows, 78,777 at +200, 97,977 at +1,000) where the indexed
  read is flat (61,945 / 61,639 / 61,639). The tabling_fib example dropped
  16.7% from 73,800 to 61,464 inferences and its twin from 99,336 to 86,995;
  every program that compiles definitions recovers its own share.

- Generic definitions compile again: `def mid[T](x: T) -> T` places `T` in
  the PEP 695 type-parameter scope, which the annotation namespace now
  includes, and the eager Space-parameter probe treats a STRUCTURED
  annotation it cannot resolve (a subscripted domain builder) as simply not
  a space handle instead of refusing the whole definition. A bare name that
  resolves nowhere keeps the loud refusal, because `target: Space` with the
  import missing must not silently turn the body's removal statements into
  arithmetic. Both regressions came from the Space-annotation feature
  resolving every parameter annotation eagerly.

- The engine layering contract names the specializer's reader edge, minted
  specialization names being symbols the reader reads back, and `translator`
  now exports `fun_meta_module/3`, the ownership question the specializer
  already asked with a module qualifier. Both edges date to the
  writable-specialization merge and had turned the layering suite red.

- Named spaces now apply lexical name hiding to stored type declarations
  during dispatch. A local declaration set replaces inherited `&self`
  declaration rows, while a local definition with no declaration takes the
  untyped path. `get-type` reporting remains additive and still exposes
  inherited declarations. A named space with no local binding retains the
  inherited typed arity refusal, and same-owner wrong-arity calls retain their
  existing refusal.

- Reconciled the phrasebook contract header so its algebra, immutable-world,
  and strategy evidence survives together instead of shipping merge markers.

- Reclaimed named MORK spaces on clear/drop and replaced the bridge's fixed
  4 GiB parser/query scratch reservations with demand-grown buffers. Joins
  beyond MORK's 63-item encoding now fall back to the engine plan instead of
  aborting the process.

- Rules bodies follow the full staging split: a defined call with ground
  arguments now runs at construction and embeds its single result
  (`fib(10)` embeds `55`; a many-answer ground call keeps its call term,
  preserving multiplicity), and a registered operation called with a rule
  variable stages the op-call term instead of running the host body on a
  Variable atom - before this, the host effect fired at construction with
  the variable in hand and the law inlined whatever the body happened to
  build, so future edits to the operation never reached the law. A ground
  op call still runs once at construction, which is the effect-visibility
  rule beside it. `examples/integration/door_combinations.metta` and its
  twin walk the whole nesting matrix cell by cell.
- Python objects now retain identity across atom construction, space storage,
  registered-operation arguments and results, and engine answers. Only exact
  `bool`, `int`, `float`, and `str` values take native by-value wire terms;
  subclasses and other objects use the interned reference carrier, which the
  answer decoder removes through the shared carrier protocol. Numeric Python
  objects are admitted at the arithmetic failure boundary and evaluated by
  Python's operator or array-namespace dispatch, so the NumPy tutorial's
  `(+ (abs -5) 10)` answers one `np.int64(15)` and a `np.float64` addition
  stays `np.float64`. The native arithmetic branch retains its previous
  inference count.
- A flat Python call of a declared function now runs the same call-site
  typed dispatch the engine's own form runs. Before this, `f(x)` on a
  compiled function with plain arguments took a direct goal that skipped
  the argument checks entirely: with `(: f (-> DemoPayload Atom))`
  declared and a user typing rule installed, `!(f unknown)` answered the
  rule's `TypingRuleRefusal` while `f(S.unknown)` and `m.eval(S.f(...))`
  answered the raw clause, and `(+ 1 "x")` through `m.eval` raised where
  the engine's form answers `(Error (+ 1 "x") (BadArgType 2 Number
  String))`. The gate reads the same declaration walk every typed call
  opens, so an undeclared function keeps its direct goal; the measured
  price of the checks is +28 inferences per rerouted declared call,
  re-pinned across the benchmark lanes with the attribution recorded in
  their baselines. The gate also declines translator-rule-owned heads,
  whose orientation gate (a bidirectional rewrite fires only when it
  lowers the form's cost) and refusals live in translation: the derived
  inverse of a bidirectional rule was blocked by cost through every
  translated door and the direct goal rewrote it anyway. The whole
  ownership question is the engine's own `metta_typed_dispatch_applies/2`
  now, one published host service any binding's direct-call door can ask
  instead of carrying its own copy of the disjunction.
- `py-call` no longer hands a callee a janus `Box`: an opaque Python
  object travelling through the shared goal-term route is unwrapped at
  the argument boundary, the same law the raw-dispatch route already
  applied, so three Python statements chained through an object between
  them run as written instead of dying with `'Box' object has no
  attribute ...` inside the callee.
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
  tree already had; after the module rename a stale `build/lib/metta`
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
  `(effect ...)`, type, and other policy atoms readable through `&metta`.

- `metta.Atom` on a registered operation parameter is now documented as an
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

- Recorded integer overflow as a deliberate host-width divergence: MeTTa and
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
  the same layout under `metta/_runtime/`, and `METTA_PATH` still names
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
  of the `metta_py_`-spelled names: the shapes are the engine's own and
  cross every host boundary, not Python's alone. A program or tool matching
  the old spellings in raw error text must follow; the structured fields on
  the `metta.errors` classes are unchanged.

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
  `metta.remote.attach(m, "&hq", url, batch=1)` puts an attached space's
  matching on the lazy door so a MeTTa `once` over it stops the serving
  engine too. `serve()` takes `cursor_idle` and `cursor_limit`, which bound
  how long an untouched cursor survives and how many stay open at once, and
  both take their defaults from SWI's `library(pengines)`, whose
  create/ask/next/stop is the lifecycle's prior art. The TypeScript
  reference servers speak revision 3 as well, and
  `metta.testing.GatewayComplianceSuite` certifies it.

- `metta.remote.Gateway` is the protocol's server side with no transport
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
  matches, and the three they disagree on keep the answer MeTTa already gave.
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
  the first one only and say nothing: `!(collapse (metta-three))` with three
  equations for the name answered `(1 2 3)` and
  `!(collapse (transaction (metta-three)))` answered `(1)`, because SWI's
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
  a Python list fired on `!(get-type (metta-effectful))`, taking a counter
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
  spells it `dosync`, and MeTTa's `transaction` is the same operation under
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
  suites load `engine/metta.pl` without `bindings/python/metta/shim.pl`. So the
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

- `MeTTa.subscribe()` takes `queue_max=`, and `metta.SubscriberError` is
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
  the error leaves the scope. It is a `MettaError`, so nothing that caught
  these before stops doing so.

  A rehydrated `MettaError` now keeps the `__cause__` it was raised with
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
  `metta.matching` and `metta.measure` after both were deleted, and
  omitted the whole `declare_*` family, `metta.spaces`,
  `metta.structures`, `metta.tables`, the manifest, the CLI and the
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
  `METTA_VERIFY_SPECIALIZATIONS` (or
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
  `metta.atoms.pretty(atom, width=78)` as its Python twin, lays a deep
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
  path paying nothing. `metta.lint.lint_file(path)` anchors each
  finding to its source form through alpha-matching and carries
  file/line/column in the payload; `python -m metta lint` prints
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
  points at the class; the `metta` logger namespace and `tqdm`
  composition each documented in one line; and the deprecation policy
  stated: a surface removal warns with `DeprecationWarning` for one
  release before it goes.
- Added `(deprecated name since remedy)` as queryable catalog data. Calling a
  matching `Defined`, `space.fn` function, or composite operator now raises a
  `DeprecationWarning` containing the catalog's version and positional remedy,
  and `explain` reflects the same declaration. Removing the row retires the
  warning immediately.
- Added `PUBLIC`/`INTERNAL` visibility rows for every shipped callable. The
  generated `fn` stub, offline help, and standard-library reference now admit
  only `PUBLIC` rows. Internal documentation and interpreter helpers remain
  reachable through exact `S[name]` and `fn[name]` mentions.
- Added the thread-safety and serialization guarantees page: per type
  and per operation, what is atomic, what locks, and what a caller must
  serialize, Python's own documentation convention pointed at MeTTa.
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
  `metta.integrations`: a package advertises a provider factory under
  `metta.spaces` or the directory of sources it ships under
  `metta.libraries`, and the app loads by NAME through
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
- Added `metta.spaces.diff(a, b)`, what `digest()` cannot say: HOW two
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
- Added `python -m metta` subcommands on the library engine, the stdlib
  "Command-line usage" chapter for the installed wheel: `run` prints
  each `!` answer group, `repl` is an interactive loop that reads
  multi-line forms (strings and comments included) and reports errors
  without dying, `serve` exposes spaces over HTTP with host/port/
  allowlist/token flags, `boot` assembles a `(boot ...)` manifest and
  blocks while its servers run, `lint` exits nonzero on findings, and
  `doc` prints a name's `(@doc ...)` documentation. The bare `metta`
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
  annotated `metta.MeTTa` is the framework's to fill, FastAPI's Depends
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
  the one true line. The engine door, `metta_py_explain`, preflights the
  same refuse guard the match consults and answers claimed/rest as
  indexes so the caller's variable names survive rendering.
- Added `metta.boot(manifest)`: deployment as knowledge. A manifest is a
  MeTTa file of `(boot ...)` forms over a closed vocabulary, each sugar
  for exactly one existing call: `(load "rules.metta")` for `m.load`
  resolved against the manifest's directory, `(attach &crm "url")` for
  `metta.remote.attach`, `(bridge &db <shape> <row>)` for a declared and
  registered `TableBridge` (live connections cross through the
  `connections=` mapping, checked both directions), and
  `(serve (&self &crm) 8700)` for `metta.remote.serve`. The whole
  manifest validates before anything performs, with every problem
  listed; forms perform in source order and each lands as its own
  `(boot ...)` atom, so the running app can query its own topology. The
  answered `Boot` handle owns the started servers and closes them, on
  the mid-way failure path too, while performed writes stand, the same
  law the engine's own guards follow. The engine door underneath,
  `metta_py_read_forms`, reads a source's forms without compiling,
  storing, or running any.
- Added a reference page for `metta.tables`, which had none, and listed
  `metta.tables`, `metta.spaces`, and `metta.structures` in the module
  index tables they were missing from. `metta.tables` now also resolves
  lazily as a package attribute like its peer modules.
- Added `@metta.record`, one decorator that makes a dataclass, NamedTuple,
  or Enum a full citizen of the type story: two-way conversion registers
  at decoration (an unregistrable class fails right there), and the
  class's `(: ...)` declarations land in the default space the moment an
  engine exists, on the first `MeTTa()` construction otherwise, so the
  decorator runs at module import time without booting anything. The
  declared class then works as a `cast` and `query(into=)` target.
  `metta.ops.class_declarations(cls)` exposes the emitted atoms, and
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
  `&metta` from boot, every written native space, every bound foreign
  space. Naming a space never registers it; writing or binding does.
- Added structured fields on the whole `MettaError` family, the way
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
- A `MettaError` raised inside a Python callback (a provider refusing a
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
- Added `metta.spaces`, combinators composing existing spaces into new
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
  `metta.run/query/add/remove/eval/fn/space` over one lazily created
  default engine, `metta.default_engine()` the named escape hatch
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
  override, and `metta.testing` exports `ground_atoms()` and
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
- Added `metta.structures`, data structures with MeTTa's semantics,
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
- Added `metta.atoms.substitute(atom, bindings)`, unify's companion:
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
  same `metta_transaction/1`, so foreign-space enlistment and nesting
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
  residues for the operand it met (`metta.foreign.CustomMatch`), and
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

- Added the typed `metta` Python package for atoms, spaces, evaluation,
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
- Added `metta.testing.SpaceComplianceSuite`, the engine's own space tests as a
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
- Added `metta.Handle`, the identity carrier for native engine values: a C
  blob reaching Python arrives as an opaque atom that resolves back to the
  very same object, so mutation and accessor calls survive the round trip
  and a Python function can unpack the structure through its extension's
  own accessors. It used to arrive silently as its printed string, which
  made the round trip impossible. `release()` frees the engine-side
  registry entry; a released handle raises by id.
- Added `metta.tables.TableBridge`, a complete table-backed space provider
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
- Added `metta.testing.GatewayComplianceSuite`, the remote protocol's own
  conformance suite: subclass it with a `gateway_url` fixture and any
  implementation, in any language, is certified against the documented
  operations, refusal ladder, wide-integer refusal, and the kit's match
  contract and round-trip law. It caught the MeTTaScript reference
  backend's unifier refusing rational-tree matches, which its server now
  covers with a soundness envelope.
- Added schemas to `metta.tables`: a provider takes any number of bridge
  declarations, shapes answering together the way overlapping equations
  do, with a ground atom two shapes admit refused by name; declarations
  can live ctx-scoped in `&metta` (`tables.declare`, or MeTTa source
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
- `metta.testing.check_space_provider`'s `atoms_to_store` now stores the
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

- Removed `metta.measure` and `metta.matching`: scored matching is the
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

[Unreleased]: https://github.com/MesTTo/MeTTa-Kernel/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/MesTTo/MeTTa-Kernel/releases/tag/v0.6.0
[1.0.5]: https://github.com/trueagi-io/PeTTa/releases/tag/v1.0.5
