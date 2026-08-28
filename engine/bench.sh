#!/bin/sh
# Purpose: the engine's own benchmark suite. It measures boot, reading,
#   translation, matching and reduction with NO host in the process at all:
#   every sample is a fresh
#   `swipl -g "metta_bench:bench_run(<case>)" -t halt engine/bench.pl`
#   and nothing else. The only other benchmark suite in this tree,
#   extensions/python/benchmarks/, reaches the engine through the Python host,
#   so until this existed an engine change's cost could only be seen with a
#   host's cost added to it and a reader or translator regression arrived
#   diluted by whatever the harness spent around it.
# Assumes:
#   - swipl, and a Python that can import metta.testing from
#     extensions/python. The comparison protocol, the two-sided band, the
#     configuration stamp and the atomic re-pin are that shared harness's and
#     are deliberately not reimplemented here [source: DEVELOPING.md:149-151].
#   - engine/reader.so, engine/writer.so and engine/json_codec.so are built,
#     and so are the chapter 19 C example artifacts, because the baseline's
#     stamp is benchmarks/configuration.py's four keys and one of them reads
#     those. `sh build.sh` at the repository root puts a tree in the pinned
#     configuration; `sh engine/build.sh` alone leaves c_extension false and
#     the run REFUSES rather than reporting a phantom move.
# Guarantees:
#   - inferences decide. They are deterministic under load, which is what lets
#     this gate run beside everything else: every case read an identical count
#     in all three samples of three consecutive runs at loadavg 9-11
#     [measured 2026-08-28].
#   - a regression beyond a case's allowance exits nonzero naming the case,
#     and so does an improvement left unpinned, because a stale-high pin masks
#     regressions up to its own margin
#     [source: extensions/python/metta/benchmarking.py, _compare_counter].
#   - a missing toolchain exits 0 with a note naming the step, the same split
#     engine/build.sh draws; a PRESENT toolchain that measures a regression
#     exits nonzero.
# Fails when:
#   - asked to compare across configurations. It refuses instead, because the
#     C reader alone moves the parse case by four orders of magnitude.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None
#
#   Usage: sh engine/bench.sh                      every case
#          sh engine/bench.sh match match-skew     named cases only
#          sh engine/bench.sh --list               the case names
#          sh engine/bench.sh --counter-only       inferences alone, no perf
#          sh engine/bench.sh --update-baseline    deliberate re-pin, prints
#                                                  what moved and by how much
#          CHECK_PY=/path/to/python sh engine/bench.sh

set -eu

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(dirname -- "$HERE")

if ! command -v swipl >/dev/null 2>&1; then
    echo "engine/bench.sh: swipl not found; the engine benchmark suite will not run" >&2
    exit 0
fi

# The same interpreter list check.sh picks from, so a bare run and a gated run
# choose the same one.
PY=${CHECK_PY:-}
if [ -z "$PY" ]; then
    for candidate in "$HOME/Dev/.venv-pypetta/bin/python" "$ROOT/.venv/bin/python" python3; do
        if command -v "$candidate" >/dev/null 2>&1; then PY="$candidate"; break; fi
    done
fi
if ! command -v "$PY" >/dev/null 2>&1; then
    echo "engine/bench.sh: no python found (set CHECK_PY); the engine benchmark \
suite will not run" >&2
    exit 0
fi

# metta.testing is the comparison protocol. A tree whose Python dependencies
# are not installed says which step is missing rather than failing for a reason
# that is not the engine.
if ! METTA_BENCH_HARNESS="$ROOT/extensions/python" "$PY" -c \
        'import os, sys; sys.path.insert(0, os.environ["METTA_BENCH_HARNESS"]); import metta.testing' \
        >/dev/null 2>&1; then
    echo "engine/bench.sh: cannot import metta.testing; run 'uv sync' in \
extensions/python. The engine benchmark suite will not run" >&2
    exit 0
fi

exec "$PY" "$HERE/bench.py" "$@"
