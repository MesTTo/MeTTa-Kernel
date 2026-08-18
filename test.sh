#!/bin/sh
# Purpose: run MeTTa examples concurrently and fail when any runner exits
#   nonzero, while retaining each example's assertion output.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None

run_test() {
    f="$1"
    echo "Running $f"
    output=$(sh run.sh "$f")
    error=$?
    assertions=$(printf '%s\n' "$output" | grep "is " | grep " should " || true)
    if [ "$error" -ne 0 ]; then
        echo "FAILURE in $f:"
        echo "$assertions"
        return 1
    else
        echo "OK: $f"
        echo "$assertions"
        return 0
    fi
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
