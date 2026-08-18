#!/bin/sh
# Purpose: prove that test.sh's "FAILURE in $f:" block carries a failing
#   example's real diagnostic, for a failure shape other than a !(test A B)
#   mismatch.
#
#   test.sh used to build that block from `grep "is " | grep " should "`
#   over stdout alone, and "is ..., should ..." is the one line !(test A B)
#   prints on a mismatch. Every OTHER failure shape, an assertEqual mismatch
#   ("Assertion failed: ..."), a syntax error, an undefined predicate, never
#   matched that filter and never entered $output to begin with, because the
#   engine reports an uncaught exception to STDERR, which test.sh did not
#   capture. The exit code still went nonzero, so the run still failed, but
#   the block printed under "FAILURE in $f:" was empty: a human reading a
#   red run saw the file name and nothing about why.
# Guarantees:
#   - a failure diagnosed only on stderr, an assertEqual mismatch's ERROR:
#     line, which never touches stdout at all, still appears after
#     "FAILURE in $f:" in test.sh's own output, not just the is/should
#     lines a passing !(test A B) prints.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None
set -eu

command -v swipl >/dev/null

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT HUP INT TERM

# assertEqual throws through assert/2 ("Assertion failed: ...", "MeTTa
# assertion failed"), never through test/3 ("is ..., should ..."), so this
# reproduces the class of failure the is/should filter was blind to.
fixture="$probe/mismatched_assert_equal.metta"
printf '!(assertEqual 1 2)\n' > "$fixture"

out=$(cd "$project_dir" && sh test.sh "$fixture" 2>&1) && rc=0 || rc=$?

if [ "$rc" -eq 0 ]; then
    echo "FAIL: test.sh exited 0 for a file whose only form is a failing assertEqual" >&2
    echo "$out" >&2
    exit 1
fi

# Only the text AFTER "FAILURE in $f:" is the claim under test. The engine's
# own ERROR: line reaches this process's stderr regardless of the fix, since
# nothing here suppresses it, so checking the WHOLE output for the
# diagnostic would pass against the broken test.sh too; what changed is
# whether test.sh's OWN block carries it.
after_failure=$(printf '%s\n' "$out" | awk '/^FAILURE in /{found=1; next} found')

case "$after_failure" in
    *"MeTTa assertion failed"*) ;;
    *)
        echo "FAIL: nothing after 'FAILURE in $fixture:' names the real diagnostic" >&2
        echo "----- full output -----" >&2
        echo "$out" >&2
        exit 1
        ;;
esac

echo "ok: test.sh's FAILURE block carries the real diagnostic, not just the is/should filter"
