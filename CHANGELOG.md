# Changelog

All notable user-facing changes to PeTTa are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The history before
1.0.5 remains available through the repository tags and release notes.

## [Unreleased]

### Added

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
  and the shipped Python library, and `python/tools/example_parity.py`
  requires them to agree. Until this lane existed the corpus only ever ran
  through the engine: the `examples` gate invokes `swipl` on `src/main.pl`,
  `test.sh` and `test_metta_examples.py` shell to `run.sh`, and the plunit
  suites load `src/metta.pl` without `python/petta/shim.pl`. So the
  configuration users ship was gated by unit tests alone, and defects lived
  there under green lanes.

  It found seven within the hour, all one root: `run()` and `load()` did not
  register a source's function signatures before processing its forms the way
  `src/filereader.pl` does, so a `!` naming a function defined LOWER DOWN in
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

### Fixed

- The engine and its libraries now declare every import they actually use,
  instead of getting several of them from SWI's autoloader by accident.
  `set_prolog_flag(autoload, false)` is Phase 11's precondition, because a
  system-based module gets library predicates from autoload rather than
  from `user`, so an incomplete export list would still be green under
  autoload and that is exactly the "modular errors slip in silently"
  failure the migration exists to prevent. Turning it off found eight real
  gaps, none in `user` code alone: `src/metta.pl`'s own
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
  already finished loading, in either order, and `src/metta.pl` needs the
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


### Changed

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

### Fixed

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

### Added

- Rewrote `llms.txt` and gated it. The file an agent reads instead of the
  tree had gone stale in the way that matters most: it named
  `m.fresh_space()` and `m.value()` after both were renamed, documented
  `petta.matching` and `petta.measure` after both were deleted, and
  omitted the whole `declare_*` family, `petta.spaces`,
  `petta.structures`, `petta.tables`, the manifest, the CLI and the
  concurrency surface. It now carries an index of every source of
  information in the repository beside the packed API, and
  `python/tools/llmsdoc.py` checks every name, path, count, special form,
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
  `python/tools/libdoc.py` generates
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
  bindings-level custom matcher (`python/examples/integration/`), and two
  production TypeScript servers speaking the remote-space protocol, one
  self-contained and one whose atoms live in a MeTTaScript space
  (`python/examples/integration/typescript_space/`, with the protocol
  itself documented in the website's live section).

### Fixed

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

### Changed

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
