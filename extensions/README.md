<!--
Purpose: the contract for adding an extension, so a seat is a folder rather
  than an entry in several lists.
Assumes: the reader is adding a folder here, not changing the engine.
  EXTENDING.md is the other document: it covers the nine points the ENGINE
  offers, where this covers the FOLDER that ships one.
Guarantees: every rule here is enforced by a named check or a named lane, and
  each says which.
-->

# Adding an extension

An extension is a folder under `extensions/` carrying an `extension.pl`. That
control file is what makes it a seat; everything else here is convention that
the gate enforces.

Nothing in the engine names your folder. The loader globs
`extensions/*/extension.pl`, the root `build.sh` and `check.sh` discover their
component scripts the same way, and `metta list` reads what is on disk. Adding
a seat needs no edit outside your own directory.

There are two documents and they answer different questions. `EXTENDING.md`
covers the nine extension POINTS the engine offers, ordered by measured cost:
translator rules, Prolog and C predicates, Python operations, reader tokens,
space providers, atom hooks, matchers, the declaration contract. This file
covers the FOLDER: what to put in it, what the scripts must do, and what will
fail if you do not.

## The control file

`extension.pl` holds FACTS the engine reads and never runs. A term outside this
vocabulary refuses loudly, naming your file and the term, because a control
file that could smuggle a directive is a script with extra steps.

```prolog
title('One line: what this seat is').

needs(artefact('relative/path/to/build/product')).   % exists_file, relative to your folder
needs(prolog_library(janus)).                        % exists_source(library(L))
needs(predicate(open_shared_object/3)).              % current_predicate; a platform door
needs(extension(mork)).                              % another seat, loaded first

entry(engine, 'bridge.pl').        % the ENGINE consults this, at boot
entry(host, 'metta/shim.pl').      % YOUR RUNTIME consults this; recorded, never loaded here
```

Every need met, and every `entry(engine, _)` loads in the file's own order and
the seat is recorded loaded. Any need unmet, and nothing loads, nothing prints,
and the unmet need is recorded where `require-extension!` can name it. **Not
built is not an error; half built is.**

Declare every artefact you need, not just the first. The MORK seat declared one
of two, and because SWI prints a raising load-time directive and carries on,
`ensure_loaded/1` still succeeded and the loader recorded the seat LOADED with
no backend behind it. Twelve of its own tests raised `Unknown procedure` on such
a tree, quietly, on every boot.

## The three axes

Offer all three, and let a program choose per call site. They are independent,
and the second and third are routinely confused.

**1. Which direction you face** is the two `entry/2` roles above. A seat may
hold either or both: Python holds both in two files, the C seat both in one,
the Node seat only `host`, MORK only `engine`. Direction of control does not
sort seats into kinds; it is a role, which is why there is one folder here.

**2. Where a definition's body lives**, CALLED or LOWERED:

| | called | lowered |
|---|---|---|
| what the engine can do | call it, nothing else | read it, specialise it, match on it |
| where the body is | your language | the engine, as equations |
| what it must declare | its effect class, since the engine cannot see in | nothing; the engine can see |
| the seats' spellings | `m.op`, `mt_def`, `op` | `@m.define`, `mt_lower`, `define` |

This is the axis `EXTENDING.md`'s cost table prices: 0.15 microseconds lowered
against 1.05 called, or 3.93 called through the wire codec. Offer both. A seat
with only the called door taxes its users 26x for writing the obvious thing.

**3. What a VALUE crosses as**, transparent or opaque, and it is NOT the axis
above wearing other words. Transparent means translated into MeTTa structure;
opaque means carried whole, as a handle the engine holds and does not read.
Opaque is first class: it keeps host identity and skips a translation that may
not be wanted, and an iterator is always opaque because measuring one drains it.
`py-atom` takes the choice as an argument, `Expression` for a snapshot and
`Grounded` for the live reference.

Two declared vocabularies sit under this axis and they are easy to confuse.
`image-mode` is `opaque`, `transparent`, `auto`, and it is what
`(image <context> <Type> <mode>)` sets per context. `registry-image` is
`expression`, `symbol`, `handle`, `operations`, and it is what a REGISTERED type
presents, one `(type-image <Type> <image>)` atom per registration. The first
answers "does this cross whole"; the second answers "what shape does the engine
see when it does not". Both are `metta_catalog_preset` rows in
`engine/spaces/catalog.pl`, so a word outside either refuses by name.

A lowered body can take an opaque argument, and a called host function can be
handed a transparent one. Do not couple them.

## Carrying a value opaquely

Axis 3's opaque half is the one with machinery behind it, so here is the
machinery. `EXTENDING.md` covers the C worked example and the blob interface
itself; this covers what YOUR SEAT must declare for its own values to cross,
which is a folder question and lands differently in each of the three.

**Most of it is already done.** `metatype_of/2`'s last clause answers `Grounded`
for anything the engine's own class tests do not claim, so a value it cannot
read is an ordinary MeTTa value with no engine change at all: it can be stored,
matched, passed and handed back. A C `mt_object` prints through its own write
callback and answers `Grounded` to `get-metatype` on that clause alone
[measured 2026-08-29 through `extensions/cetta`].

**What is not done is the TYPE.** `get_type_candidate/2` reaches a host object
through `seam:host_object/1` and by no other clause, and the difference is
visible:

| | `get-metatype` | `get-type` |
|---|---|---|
| C `mt_object`, no `host_object` clause | `Grounded` | `%Undefined%` |
| Python object, with one | `Grounded` | `[datetime, date, Grounded]` |

Declaring the clause is what makes your values TYPED to MeTTa, and
`EXTENDING.md` names it as one of the four seams by which a whole host plugs in,
with the Python bridge as the worked example. Leaving it out is survivable and
the C seat currently does: its values are grounded, storable and matchable, and
`%Undefined%` is what `get-type` says about them. That is a decision to make on
purpose rather than one to inherit by omission, and it costs a table row in your
seat's own prose either way.

The Python row is the shipped class walk [tested: `metta_object_types`]. The C
row is measured and has no test behind it, deliberately: pinning `%Undefined%`
would make this seat's typelessness a contract, and it is a decision still open
[measured 2026-08-29: the same two questions asked of `mt_object` and of
`(let $o (py-atom "...datetime(2020,1,1)" Grounded) (get-type $o))`].

**Which shape your handle takes decides what the seam buys you.** There are two,
and both ship:

- **an SWI blob**, which the C and Python seats use. It is `atomic` and not
  `atom`, which is exactly the pre-test `get_type_candidate/2` applies before
  consulting the seam, so a blob with a `host_object` clause reaches
  `metta_grounded_type/2` and gets a real type.
- **an atom-shaped id**, which the Node seat uses: `'$metta_node_object#7'`,
  with the object held on its side. An atom fails that pre-test, so no type
  arrives this way. What the seam buys here is the METATYPE: without the clause
  `metatype_of/2` would reach its `atom(X)` case first and call your handle a
  `Symbol`, which is the bridge's own reason for having one.

**The seats' spellings**, since this is the axis a reader comes here to compare:

| | C | Python | Node |
|---|---|---|---|
| make one | `mt_object(v, "Type", release)` | return the object; `py-atom <e> Grounded` from MeTTa | `G(value)`, any non-primitive |
| read it back | `mt_value`, `mt_type` | the object itself | the object itself, `===` |
| what carries it | blob `cetta_object` | an SWI blob | an id atom |
| declares `host_object/1` | no | yes | yes |

**Round-trip identity is not the same question as wrapping identity, and you
must answer the second yourself.** Round trip holds everywhere: the value that
comes back is the one you put in, and a C pointer stored in a space and matched
out again is the very same pointer [tested:
`extensions/cetta/tests/test_cetta.c`, "a live C value crosses MeTTa and comes
back the same object"]. Wrapping the same value TWICE is where the seats differ.
Node interns by identity through a `WeakMap`, so `G(x) === G(x)` for one object
and the engine-side handle table holds one entry per object. Python answers
`True` to `==` for two `py-atom` reads of one object. C does not intern:
`mt_eq` compares the box `mt_object` allocates per call, so two calls on one
pointer answer `False` to `==` and fail to `unify` [measured 2026-08-29, the C
and Python answers; the Node behaviour is read from `extensions/node/src/atom.ts`,
`byReference`].

Which way to go follows from the shape you chose. An id-shaped handle is backed
by a table on your side, so interning keeps that table one entry per object
instead of one per crossing, which is Node's stated reason for the `WeakMap`. A
blob has no such table and is released by SWI's own garbage collector, so not
interning costs no memory; what it costs is that two wraps of one value are two
MeTTa values that compare unequal. Either way, say which in your seat's own
prose, and wrap once and pass the atom.

**Own the lifetime.** A blob's release callback is where the structure is freed
when SWI garbage-collects the handle, and without one every handle leaks.
`PL_BLOB_NOCOPY` means SWI keeps the pointer you hand it, so hand it heap memory
and never the address of a local. On the Python side `release()` retracts the
registry entry keeping the blob alive, and a released handle raises by id rather
than answering wrongly.

**`host_object/1` is an OWNERSHIP seam, which sets three rules.** The first
success claims the value, so recognise only your own and let everything else
fail. It may cut after that test, unlike an event seam, and
`no_cut_in_an_event_hook` checks the distinction rather than banning cuts. And
it sits in front of every grounded-type lookup, so its cost is paid at each of
them and not once per seat. What that is worth is measured on the sibling
ownership seam: the Node bridge's `seam:foreign_space/1` cost exactly one
inference on every space operation whether or not any provider existed, 239,005
against 238,505 on that seat's `define-call` benchmark. Write the guard so a
failure costs one indexed lookup.

**If your objects can be CALLED, say so.** `seam:grounded_applicable/1` answers
whether a value is applicable and `seam:grounded_apply/3` applies it, which is
how `($f 2)` works wherever the atom lands. The C seat's pair is two clauses over
`blob(Obj, cetta_object)`, and it is what C answers to a Python callable being
an atom.

**Why bother.** Reading one element of a thousand-element vector through a
handle costs 0.1968us and 2.00 inferences; writing that vector as text costs
389.94us and 16,906 inferences and reading it back costs 919.35us and 44,600
[measured 2026-08-16]. The handle's cost is flat in the structure's size and the
text's is linear. `EXTENDING.md` has the C worked example and
`examples/ch19-spaces-backed-by-anything/19-03-a-builtin-in-c/` the runnable
one.

## The folder

| path | what it is | required |
|---|---|---|
| `extension.pl` | the control file | yes; it is what makes this a seat |
| `llms.txt` | the consumer's cheat sheet: install, first call, the surface | yes, checked |
| `README.md` | the seat's own prose, published on the site | yes for a host seat |
| `build.sh` | build your artefacts | if you have any |
| `check.sh` | your gate lanes, SOURCED by the root gate | yes |
| `test.sh` | your tests, the same entry the gate uses | if you own tests |
| `bench.sh` | your suite against committed pins | if you own benchmarks |
| `tests/` | tests whose subject is this seat | yes |
| `examples/` | runnable programs a reader can copy, plural | yes for a host seat |
| `examples/language-feature-examples/` | the shipped MeTTa corpus written again in this host, one file per example | if the seat mirrors the corpus |
| `benchmarks/` | the suite plus `baseline.json` | yes if `bench.sh` exists |
| `kit/` | the codec conformance corpus and its driver | for a host seat with a wire |

The tree is not yet uniform on two of these: the Node seat spells its test
directory `test/` in the singular, and the Python seat ships no `README.md`.
Follow the plural, and write the README.

`language-feature-examples/` is where a seat proves it can express the whole
language rather than a chosen tour of it. The Python seat carries one, 219 files
mirroring `examples/` path for path, each defining `twin(m)` and pinned to an
inference budget that `tools/twin_coverage.py` measures; the Node and C seats
answer the shipped corpus from the Python side instead, through
`extensions/python/tests/ch21_another_language_at_the_seam/`, so neither ships
a folder of its own yet. A seat that grows one puts it here, under `examples/`,
because it IS examples: the same programs a reader already knows, in a
different host. Say in the folder's README how they run, since a corpus driven
by a tool is not a corpus you execute file by file.

## The five scripts, and the one rule they share

`build.sh`, `check.sh`, `test.sh`, `bench.sh` and `run.sh` are the contract the
`metta` CLI's verbs delegate to. Every one of them draws the same split:

- a toolchain that is **ABSENT** exits 0 with a note naming the step that is
  missing, because a gate that reaches the network or demands a compiler fails
  for a reason that is not the tree;
- a step that is **ATTEMPTED and FAILS** exits nonzero.

Write the note so it says the exact command to run: `npm ci --prefix
extensions/node`, not "dependencies missing".

`check.sh` is SOURCED by the root gate, not executed. That is what lets it use
`run`, `$HERE` and the shared summary table, and it is why one component's lane
cannot report its status differently from another's. Write every path
LITERALLY: `tests/checks/evidence_runners.py` models which files a lane covers
by reading that text, so a path reached through a variable is a path the
evidence gate cannot see.

Have `check.sh` call `test.sh` and `bench.sh` rather than repeating their
commands. The gate and a developer should run one file. When the Python seat's
pytest flags lived in the lane alone, running `pytest` by hand used different
settings from the ones that make the run correct.

## Tests

Own the tests whose subject is your seat. Drive your public doors rather than
reaching into internals, and cover the paths a built tree cannot reach: what
happens with your artefact absent, with a need unmet, with the seat present and
its backend broken.

A test that can SKIP is not evidence until its output proves it ran. Report a
count, and fail a built tree that reported fewer tests than the file declares.
A worktree has no gitignored build output, so a lane that skips there reads
green while proving nothing.

A host seat also passes the codec conformance kit: `kit/corpus.json` and its
driver, which `extensions/python/tests/ch21_another_language_at_the_seam/`
compares across seats so two languages cannot disagree about what an atom is.

## Benchmarks

**Do not write a harness.** Import `BenchmarkBaseline`, `benchmark_case`,
`count_atoms` and `measure_instructions` from `metta.testing`; `DEVELOPING.md`
says so and every seat's suite is a thin driver over it. It already gives you
minimum-of-three with fresh setup per sample, a two-sided band where a stale
high pin fails as well as a regression, configuration stamps that refuse rather
than misreport, and perf measurement that fails loudly.

**Choose the deciding counter by where the work happens.** Inference counters
are deterministic under load, which is why they decide wherever the engine does
the work: one workload measured 1,000,601 inferences on five consecutive runs
while wall clock moved 6.86%. But **they are blind across a foreign boundary**,
because foreign code retires none. This tree has the failure on record: a C wire
encoder measured 526x faster by inferences while CPU said it was 1.8x SLOWER.
So a case that crosses into C, Rust or WebAssembly is decided by
`perf stat -e instructions:u` and CPU time, paired, and inferences are pinned
beside them as a third reading of what the ENGINE did. Wall clock never decides.

**Stamp the configuration.** A pin is comparable only within the configuration
it was taken in, and the stamp is what refuses instead of reporting a phantom
regression. Stamp everything that moves your numbers: the C artefacts move one
case by four orders of magnitude, and the loaded SEAT SET moves a boot by 23,155
inferences and every space operation by two. Ask the engine which seats loaded
rather than modelling the rule.

**Say where it was measured.** Instruction counts move with the checkout's path
length: the same case reads 853,856,877 from a 72-character worktree path and
832,667,280 from a 30-character one, 2.51% apart, with inferences identical. Pin
from the main checkout.

## What the gate will check

Named, so you know what turns red rather than discovering it:

- `test_the_tree_partitions_by_seam` and its neighbours: a component owning a
  test directory ships `test.sh`; one shipping a benchmark suite ships its
  baseline; every seat ships an `llms.txt`.
- `test_every_extension_has_a_site_area`: every seat has a page under
  `website/extensions/`.
- `every_seam_declares_one_kind` and `every_seam_kind_matches_its_direction`:
  a seam clause you contribute, `seam:host_object/1` among them, is declared
  with one kind and on the right side of the wire.
- `no_cut_in_an_event_hook`: your cut is allowed in an ownership seam and
  refused in an event or declaration one, which is the distinction that keeps
  a later-loaded clause reachable.
- the `evidence` lane: every claim in a header names a test a runner executes.
- the `codespell`, `ruff-drivers` and `docs` lanes reach your files.
- your own lanes, from `check.sh`, sourced into the same summary table.

## The smallest seat that works

```
extensions/mine/
  extension.pl      title/1, at least one needs/1 or entry/2
  llms.txt          how a consumer uses it
  README.md         what it is
  check.sh          run GATE mine-tests sh "$HERE/extensions/mine/test.sh"
  test.sh           your tests, with a count
  tests/
```

Add `build.sh` when you have something to compile, and `bench.sh` with a
`benchmarks/baseline.json` when you have something worth holding to a number.
