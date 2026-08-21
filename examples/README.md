# MeTTa examples by topic

Each MeTTa file is runnable from the repository root. For example:

    sh run.sh ./examples/basics/fib.metta

Run the self-checking corpus with:

    sh test.sh

`test.sh` discovers examples recursively. It excludes `_fixtures` and the six
interactive, network-backed, or optional-dependency examples named in the
runner. The merged corpus contains 218 examples that run in the shell suite.
That count is `len(example_parity.corpus())`, the corpus's one definition in
`bindings/python/tools/example_parity.py`; the `pytest` gate lane fails the moment
this sentence and the tree disagree. Selected root paths remain as symlink
aliases for package differential tests and existing documentation. Each
canonical source file lives in one topic folder, and recursive discovery
does not run an alias twice.

| folder | subject |
|---|---|
| `basics/` | arithmetic, Boolean forms, recursion, strings, and the REPL |
| `control/` | conditionals, case, let, nondeterminism, sequencing, and evaluation |
| `data/` | atom, list, set, fold, iterator, and stream operations |
| `functions/` | higher-order calls, currying, partial application, and specialization |
| `integration/` | file, git, Prolog, Python, LLM, and PyTorch boundaries |
| `libraries/` | crypto, HE, memoization, regex, Roman, Patrick, date, and tabling libraries |
| `performance/` | larger workloads and optimized variants |
| `reasoning/` | logic programs, constructive negation, Peano arithmetic, PLN, NARS, measures, and puzzles |
| `spaces/` | matching, inherited, restricted, and expression-named execution contexts, child-first reads with front-only writes, parameters through `context-space`, the row snapshot a match takes before its templates run, mutation, transactions, state, evaluating in a named space, delegating to a shadowed definition with `super`, rewrite systems, pre-add hooks, and admission pools with the judge's MeTTa/builtin differential |
| `syntax/` | parsing, rendering, comments, and string edge cases |
| `translation/` | call, quote, eval, reduce, translator rules, and staged execution |
| `types/` | concrete, parametric, recursive, dependent, and nondeterministic types |

`integration/_fixtures/` contains imported MeTTa, Python, and Prolog helper
files. They are dependencies of the integration examples, not standalone
programs. One of them, `git_fixture.pl`, builds a throwaway local git
repository so `git_import.metta` exercises acquisition without a network.
