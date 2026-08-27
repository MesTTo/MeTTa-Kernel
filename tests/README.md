# What is where under `tests/`

Everything here is run by `check.sh`, which is the one gate. Nothing in this
directory is a pytest module: the Python suite lives in
`bindings/python/tests/` and is organised by the same 22-chapter spine the
examples use.

| directory | what it holds |
|---|---|
| `checks/` | the Python gate scripts, each with the selftest that proves it can fail, plus `evidence_runners.py`, the model of what this repository's runners execute |
| `shell/` | every `test_*.sh` suite, including the four regression reproductions that used to sit in a `regression/` folder of their own |
| `prolog/` | the engine's Prolog tests: `suites/<group>/*.plt` and, at the top level, the analysis machinery they load |
| `conformance/` | the two arbiters, LeaTTa and the CeTTa fork, and the corpora they read |
| `fixtures/` | inputs rather than programs: the specializer reproductions, the no-autoload boot, the two parity drivers |
| `data/` | pinned data every runner reads: `example_skips.txt` and the upstream parity baseline |
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

    :- ensure_loaded('../../../../engine/metta.pl').        % file-relative
    :- initialization(consult('../../engine/metta.pl')).    % cwd-relative

and both name the same file. Run one suite by hand the way `check.sh` does,
from `tests/prolog`:

    cd tests/prolog && swipl -g "set_test_options([format(log)]), run_tests" \
        -t halt suites/reader/parser.plt

Run it from anywhere else and SWI finds the load-time half through its
deprecated working-directory fallback and says so.
