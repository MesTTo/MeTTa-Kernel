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

**3. What a VALUE crosses as**, transparent or opaque. This is a declared engine
vocabulary, `(vocabulary registry-image expression symbol handle operations)`,
and it is NOT the axis above wearing other words. Transparent means translated
into MeTTa structure; opaque means carried whole as a blob the engine holds and
does not read. Opaque is first class: it keeps host identity and skips a
translation that may not be wanted, and an iterator is always opaque because
measuring one drains it. `py-atom` takes the choice as an argument, `Expression`
for a snapshot and `Grounded` for the live reference.

A lowered body can take an opaque argument, and a called host function can be
handed a transparent one. Do not couple them.

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
| `examples/` | runnable programs a reader can copy | yes for a host seat |
| `benchmarks/` | the suite plus `baseline.json` | yes if `bench.sh` exists |
| `kit/` | the codec conformance corpus and its driver | for a host seat with a wire |

The tree is not yet uniform on two of these: the Node seat spells its
directories `test/` and `example/` in the singular, and the Python seat ships no
`README.md`. Follow the plural, and write the README.

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
