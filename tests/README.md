# What is where under `tests/`

Everything here is run by `check.sh`, which is the one gate. Nothing in this
directory is a pytest module: the Python suite lives in
`extensions/python/tests/` and is organised by the same 22-chapter spine the
examples use.

| directory | what it holds |
|---|---|
| `checks/` | the Python gate scripts, each with the selftest that proves it can fail, plus `evidence_runners.py`, the model of what this repository's runners execute |
| `shell/` | every `test_*.sh` suite, including the four regression reproductions that used to sit in a `regression/` folder of their own |
| `prolog/` | the engine's Prolog tests: `suites/<group>/*.plt` and, at the top level, the analysis machinery they load |
| `conformance/` | the two arbiters, LeaTTa and the CeTTa fork, and the corpora they read |
| `fixtures/` | inputs rather than programs: the specializer reproductions, the no-autoload boot, the two parity drivers |
| `data/` | pinned data every runner reads: `example_skips.txt`, the upstream parity baseline, and `syntax_introductions.txt` |
| `codec/` | the wire codec conformance corpus, which ships inside the wheel |

## The Prolog suites

`tests/prolog/suites/` groups the 46 plunit suites by the engine unit each one
tests, so a group name is the engine's own word rather than a new taxonomy:
`reader/`, `translator/`, `evaluation/`, `spaces/`, `libraries/`, `host/`,
`seams/`, `metatheory/`.

The `.pl` files stay at `tests/prolog/`. That is deliberate rather than
unfinished: `surface_walk.pl` is loaded by six of them, `static_checks.pl` by
five, and five files are BOTH a script `check.sh` invokes and a library another
script loads, so splitting them into "gates" and "support" would be a false cut
with twenty broken relative loads behind it.

**Two path depths, and which is which.** A suite resolves a LOAD-time
directive, `:- ensure_loaded(...)`, against its own file, and a RUN-time goal,
`initialization(consult(...))` or anything a test body builds, against the
WORKING DIRECTORY. The runner keeps that directory at `tests/prolog`, so a
suite two levels down writes

    :- ensure_loaded('../../../../engine/qlf_boot.pl').     % freshness first
    :- ensure_loaded('../../../../engine/metta.pl').        % file-relative
    :- initialization(consult('../../engine/metta.pl')).    % cwd-relative

and both name the same file.

**`qlf_boot.pl` comes first, and it is not optional.** The engine's units are
consulted by umbrellas, so `engine/spaces/foreign.pl`'s clauses are compiled
into `engine/spaces.qlf` and SWI's own staleness check compares that artifact
against `engine/spaces.pl` alone. Edit a unit and the umbrella stays fresh by
mtime, so a suite loading `engine/metta.pl` directly gets the OLD code and
passes against it. `engine/main.pl` loads the purge that defeats this, and
`check.sh` warms one boot through it before any lane, but a suite run by hand
or through `engine/test.sh` alone reaches neither. Loading `qlf_boot.pl` before
the engine makes each suite correct on its own; `tests/checks/check_qlf_freshness.py`
refuses a loader that omits it. Run one suite by hand the way `check.sh` does,
from `tests/prolog`:

    cd tests/prolog && swipl -g "set_test_options([format(log)]), run_tests" \
        -t halt suites/reader/parser.plt

Run it from anywhere else and SWI finds the load-time half through its
deprecated working-directory fallback and says so.

## The cumulative-syntax law

`examples/` teaches in one order, and the law says so: **a file may use only
constructs introduced at or before its own number.** Three pieces enforce it.

`tests/prolog/example_constructs.pl` reads a `.metta` file through the ENGINE's
own parser and keeps only the heads the ENGINE publishes, `builtin_fun/1` and
`metta_special_form_head/1` plus `!`. Neither of those two answers for the
other, so both are asked: `builtin_fun/1` does not know `if` or `case`, and the
special-form service does not know `+` or the `#`-prefixed arithmetic family.
A program's own function names are not constructs and are not reported.

`tests/data/syntax_introductions.txt` is the introduction table, one row per
construct, in teaching order. It is CHECKED IN, and that is the point: derived
on the fly the law is vacuous, because "introduced" would mean "first used" and
every use would satisfy it by construction. Held as data, the same law catches
a file moved earlier than the construct it needs. Its comment character is
MeTTa's `;`, because `#*`, `#+`, `#<` and twelve more are construct NAMES.

`tests/checks/check_cumulative_syntax.py` compares the two, and also checks
that no row is stale or misplaced, that no row names something the language
does not have, and that the spine's measured dependency floor holds: where
every file using A also uses B and B is more common, B may not be introduced
after A. `--write` regenerates the table, so accepting a deliberate change to
the teaching order is one command and a reviewable diff.

The lane carries a PERMANENT negative control inside the corpus,
`examples/ch01-getting-started/_fixtures/01-reaches-forward.metta`: a chapter-1
file using a chapter-15 and a chapter-22 construct. The lane fails if it ever
stops catching it. `_fixtures/` is excluded by every runner's own find, so the
control never runs, never counts as an example, and never enters the table.

The `:` and `->` of a type declaration are outside all of this. The engine
publishes them as neither a builtin nor a special form, so the law does not
reach them; adding them by hand would be a second vocabulary that drifts.
