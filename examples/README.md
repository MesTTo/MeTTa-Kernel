# The MeTTa examples, in reading order

Every file here runs, and every file here checks itself. They are the
semantics documentation and the test suite at the same time, which is why
`(test ...)` appears in nearly all of them and why nothing in this directory
can go stale without a lane going red.

Run one:

    sh run.sh ./examples/ch02-programming-a-family-tree/04-the-whole-program.metta

Run all of them:

    sh test.sh

## How the numbers work

The directory names are the reading order, so a listing is the index:

    examples/ch07-control-flow/07-02-case/03-caseconstrain.metta
             ^chapter          ^section    ^order within the section

A chapter without sections holds its files directly. A section repeats its
chapter's number, the way the Rust book's `listing-07-02` does, so a
coordinate is unambiguous wherever you find it.

**A file uses only what an earlier number introduced.** That is the law the
whole ordering exists for, and it is checked rather than asserted:
`tests/checks/check_cumulative_syntax.py` reads every file's head-position
forms through the engine's own parser and fails when one reaches forward.
`tests/data/syntax_introductions.txt` is the table it reads, one row per
construct, naming the coordinate that introduces it, and it is checked in
rather than derived, because a table read out of the corpus would make the
law true by definition. `tests/README.md` explains the three pieces.

The lane carries a permanent negative control INSIDE this corpus,
`ch01-getting-started/_fixtures/01-reaches-forward.metta`, a chapter-1 file
using a chapter-15 and a chapter-22 construct, and fails if it ever stops
catching it. Do not fix that file.

Two chapters have no MeTTa examples of their own and so have no directory
here: 13 (a queryable dataset) and 21 (another language at the seam) are
Python and TypeScript. The numbering keeps their places rather than closing
the gaps, because the same 22 chapters order the Python tests and the
website.

## The chapters

| chapter | subject |
|---|---|
| `ch01-getting-started` | `!`, the first answer, and the checking form the rest of the corpus is written in |
| `ch02-programming-a-family-tree` | one whole program in four steps, everything forward-referenced |
| `ch03-atoms-and-expressions` | comments, strings, reading source and printing it back |
| `ch04-spaces-and-matching` | a space is where a program lives; patterns, bindings and templates |
| `ch05-equations-and-evaluation` | `=` as a rewrite, changing the equations, arithmetic including the relational family |
| `ch06-many-answers` | `superpose`, `collapse`, `once`, `empty`: multiplicity is meaning |
| `ch07-control-flow` | `if` and the booleans, `case`, `let` and sequencing, bounded and committed searches, recursion |
| `ch08-data` | atoms, lists and folds, sequence variables, the shipped MeTTa libraries |
| `ch09-types` | declarations, `get-type`, parametric, recursive, dependent and nondeterministic types |
| `ch10-errors-and-refusals` | an error is data, and where it raises |
| `ch11-python-as-a-notation` | `py-atom`, `py-call`, the Python surface from the MeTTa side |
| `ch12-testing` | the assertion family and equality by reduction |
| `ch14-seeing-your-program` | pragmas, timing, inference counts, the console |
| `ch15-writing-transactions-and-worlds` | mutation, state, transactions, pre-add hooks, admission |
| `ch16-events-and-standing-queries` | the event layer's declared delivery and reaction rows |
| `ch17-concurrency-and-the-loop` | threads, mutexes, Linda, `hyperpose` |
| `ch18-performance` | larger workloads, memoisation and tabling, algebra carriers |
| `ch19-spaces-backed-by-anything` | inherited, restricted and parametric spaces; a space and a builtin in C |
| `ch20-extending-the-engine` | translator rules, MeTTa written in MeTTa, Prolog underneath, modules and the `&metta` catalog |
| `ch22-a-reasoner-you-can-serve` | logic programs, weighted answers, search |

## What does not run

`test.sh` discovers examples recursively. It excludes `_fixtures` and the six
interactive, network-backed, or optional-dependency examples named in
`tests/data/example_skips.txt`, each with its reason.
The merged corpus contains 232 examples that run in the shell suite.
That count is `len(example_parity.corpus())`, the corpus's one definition in
`extensions/python/tools/example_parity.py`; the `pytest` gate lane fails the
moment this sentence and the tree disagree.

A `_fixtures/` directory sits beside the chapter that imports it and holds
inputs rather than programs: imported MeTTa, Python and Prolog helper files,
including one, `git_fixture.pl`, that builds a throwaway local repository so
the `git-import!` example exercises acquisition without a network.

The Python-first executable gallery lives in
`extensions/python/examples/gallery/`. Its six programs carry checked per-claim
translation and output comments and run in the blocking `gallery` lane. They
add no `examples/**/*.metta` files, so the count above is unchanged.
