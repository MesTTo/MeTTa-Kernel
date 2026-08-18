#!/bin/sh
# Purpose: run MeTTa examples concurrently and fail when any runner exits
#   nonzero, printing each example's (test ...) trace when it passes and its
#   whole output, unfiltered, when it does not.
# Guarantees:
#   - a failing example's real diagnostic reaches the "FAILURE in $f:" block,
#     stdout and stderr both, rather than only the lines a passing (test A B)
#     happens to print [tested tests/test_example_runner_surfaces_failures.sh]
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None

run_test() {
    f="$1"
    echo "Running $f"
    # 2>&1: an assertEqual mismatch throws through assert/2, which prints
    # "Assertion failed: ..." to STDOUT but reports the uncaught exception to
    # STDERR ("... MeTTa assertion failed ..."), and a syntax error or an
    # undefined predicate never prints an is/should line at all. Capturing
    # stdout only, the way this read before, meant every one of those failure
    # shapes showed as a blank body under "FAILURE in $f:": the diagnostic
    # either never entered $output or was filtered back out below, and only a
    # !(test A B) mismatch (the one shape that prints "is ..., should ...")
    # ever survived to be shown.
    output=$(sh run.sh "$f" 2>&1)
    error=$?
    if [ "$error" -ne 0 ]; then
        echo "FAILURE in $f:"
        echo "$output"
        return 1
    fi
    echo "OK: $f"
    # Filtered here and only here: a passing file has nothing else worth
    # reading, and the unfiltered trace is long. examples/basics/math.metta
    # alone prints 273 lines for five (test ...) forms [measured 2026-08-18].
    assertions=$(printf '%s\n' "$output" | grep "is " | grep " should " || true)
    echo "$assertions"
    return 0
}

pids=""
work=$(mktemp -d "${TMPDIR:-/tmp}/metta-example-runner.XXXXXX") || exit 2
pidfile="$work/pids.tsv"
filelist="$work/examples.txt"
trap 'rm -rf "$work"' EXIT HUP INT TERM

if [ "$#" -eq 0 ]; then
    find ./examples -type f -name '*.metta' \
        ! -path '*/_fixtures/*' -print | LC_ALL=C sort > "$filelist"
else
    printf '%s\n' "$@" > "$filelist"
fi
[ -s "$filelist" ] || { echo "test.sh: no examples found" >&2; exit 2; }

# The skips come from tests/example_skips.txt, which is the one definition
# every runner reads. They used to be six basenames here and seven in
# check.sh, two copies that disagreed, and matching on BASENAME silently
# skips any future example that happens to share a name with one of these.
SKIPS=$(command grep -v '^#' tests/example_skips.txt | awk 'NF {print $1}')

while IFS= read -r f; do
    rel=${f#./}
    case "
$SKIPS
" in *"
$rel
"*) continue ;;
    esac
    run_test "$f" &
    pid=$!
    pids="$pids $pid"
    printf '%s\t%s\n' "$pid" "$f" >> "$pidfile"
done < "$filelist"

status=0
for pid in $pids; do
    if ! wait "$pid"; then
        failed_file=$(awk -F '\t' -v wanted="$pid" '$1 == wanted { print $2; exit }' "$pidfile")
        echo ""
        echo "==============================="
        echo "Stopping tests due to failure:"
        echo "❌ Failed test: $failed_file"
        echo "==============================="
        kill $pids 2>/dev/null
        status=1
        break
    fi
done

exit $status
