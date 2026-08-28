#!/bin/sh
# Purpose: run every component's benchmark suite against its committed
#   baselines, and fail when any of them reports a regression.
# Assumes:
#   - a component owns its own measurements. This file knows how to FIND a
#     suite and how to report the set of them; what a case is, which counter
#     decides it and what its allowance is belong to the component, because
#     only it knows whether its work crosses a foreign boundary where inference
#     counters read zero.
#   - each component's bench.sh exits 0 when its suite passes, nonzero on a
#     regression, and exits 0 with a note when its toolchain is absent. That is
#     the same split build.sh and check.sh already draw, and for the same
#     reason: not present is not an error, half present is.
# Guarantees:
#   - suites are DISCOVERED, so adding one is a file in a component rather than
#     an entry here, which is the rule the engine applies to a control file and
#     build.sh applies to a build
#   - every suite runs even after one fails, and the failures are named
#     together at the end. A benchmark run that stops at the first regression
#     hides how many there are.
#   - arguments pass through to every suite unchanged, so
#     `sh bench.sh --update-baseline` re-pins each one through its own updater
#   - this is not the upstream comparison. That is tests/upstream_bench.sh,
#     which runs the shared example corpus against a git ref on both engines;
#     it answers a different question and keeps its own name.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None

set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)

found=''
failed=''
for component in "$HERE/engine" \
                 "$HERE"/extensions/*/ \
                 "$HERE"/examples/ch19-*/; do
    script="${component%/}/bench.sh"
    [ -f "$script" ] || continue
    name=$(printf '%s' "${component%/}" | sed "s|^$HERE/||")
    found="$found $name"
    printf '\n=== %s ===\n' "$name"
    if ! sh "$script" "$@"; then
        failed="$failed $name"
    fi
done

if [ -z "$found" ]; then
    echo "bench.sh: no component ships a bench.sh yet" >&2
    echo "  A component's benchmarks live beside it, and this discovers them:" >&2
    echo "  engine/bench.sh, extensions/<seat>/bench.sh." >&2
    exit 0
fi

printf '\n================ benchmarks ================\n'
printf 'suites ran:%s\n' "$found"
if [ -n "$failed" ]; then
    printf 'REGRESSED:%s\n' "$failed" >&2
    exit 1
fi
echo 'no regressions'
