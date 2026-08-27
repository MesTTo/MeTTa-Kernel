#!/bin/sh
# Purpose: run MeTTa examples concurrently and fail when any runner exits
#   nonzero, printing each example's (test ...) trace when it passes and its
#   whole output, unfiltered, when it does not.
# Guarantees:
#   - a failing example's real diagnostic reaches the "FAILURE in $f:" block,
#     stdout and stderr both, rather than only the lines a passing (test A B)
#     happens to print, and the three failure shapes stay tellable apart there:
#     a (test A B) mismatch by its is/should line, an assertEqual mismatch by
#     "MeTTa assertion failed", a syntax error by "Syntax error"
#     [tested tests/shell/test_example_runner_surfaces_failures.sh]
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None

run_test() {
    f="$1"
    echo "Running $f"
    # 2>&1, because only ONE failure shape says anything on stdout. A
    # !(test A B) mismatch prints "is ..., should ..." there, and does so
    # because test/3 prints that line on success too: it is a trace of a check
    # that RAN, not a failure report. Every other shape is diagnosed on stderr
    # alone. An assertEqual mismatch reports "MeTTa assertion failed" through
    # print_message/2 -- it used to print "Assertion failed: ..." to stdout as
    # well, which an embedded host could neither suppress nor separate from its
    # own output -- and a syntax error or an undefined predicate never touches
    # stdout at all. Capturing stdout only, the way this read before, left
    # every one of those shapes as a blank body under "FAILURE in $f:": the
    # file name and nothing about why.
    # tests/shell/test_example_runner_surfaces_failures.sh runs all three shapes and
    # a passing file through this script AND through a copy of it with this
    # one redirection removed, so what the 2>&1 buys is measured rather than
    # asserted here.
    # A wall ceiling per example, because this lane green-masked two
    # evaluator regressions that turned seconds-scale examples into
    # half-hour crawls (invertpeanoplus and tilepuzzle, 2026-08-25): with
    # no bound, a catastrophic slowdown still exits 0 and reads as OK.
    # The slowest example clears 30s on a loaded box; 290 leaves room for
    # contention while still failing anything in a different cost class,
    # and timeout's exit 124 reaches the FAILURE block like any other red.
    output=$(timeout 290 sh run.sh "$f" 2>&1)
    error=$?
    if [ "$error" -ne 0 ]; then
        echo "FAILURE in $f:"
        echo "$output"
        return 1
    fi
    echo "OK: $f"
    # Filtered here and only here: a passing file has nothing else worth
    # reading, and the unfiltered trace is long. examples/ch05-equations-and-evaluation/05-03-the-number-library/01-math.metta
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

# The skips come from tests/data/example_skips.txt, which is the one definition
# every runner reads. They used to be six basenames here and seven in
# check.sh, two copies that disagreed, and matching on BASENAME silently
# skips any future example that happens to share a name with one of these.
SKIPS=$(command grep -v '^#' tests/data/example_skips.txt | awk 'NF {print $1}')

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
