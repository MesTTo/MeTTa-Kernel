#!/bin/sh
# Purpose: prove that test.sh's "FAILURE in $f:" block carries each failure
#   shape's own diagnostic, that the three shapes stay tellable apart there,
#   and that a passing file still reports its is/should trace and nothing else.
#
#   test.sh used to build that block from `grep "is " | grep " should "` over
#   stdout alone, and "is ..., should ..." is the one line !(test A B) prints.
#   Every OTHER failure shape never matched that filter and never entered
#   $output to begin with, because the engine reports them to STDERR, which
#   test.sh did not capture. The exit code still went nonzero, so the run still
#   failed, but the block printed under "FAILURE in $f:" was empty: a human
#   reading a red run saw the file name and nothing about why.
#
#   Only one shape says anything on stdout now. test/3 prints its is/should
#   line on success too, so that line is a trace of a check that RAN. An
#   assertEqual mismatch is stderr-only since engine/metta/runtime.pl routed
#   its report through print_message/2, and a syntax error always was. So the
#   2>&1 in test.sh went from carrying part of one shape to carrying two whole
#   ones, and that is what the crippled copy below measures.
# Guarantees:
#   - a !(test A B) mismatch, an assertEqual mismatch and a syntax error each
#     reach the "FAILURE in $f:" block naming THEMSELVES, and none of the three
#     bodies carries another's signature
#   - a passing file's report is the is/should trace, without the engine's
#     compiled-goal listing that the same $output holds
#   - the stdout+stderr capture is load-bearing for two of those three shapes,
#     proven against a copy of test.sh with that one redirection removed rather
#     than asserted in a comment. The same copy still reports the is/should
#     shape, so the two negative results are the redirection's doing and not a
#     broken script's
# Fails when:
#   - test.sh's capture line is reworded so the crippled copy comes out
#     identical to the original. That is caught and reported rather than
#     passing quietly, because an unmodified copy would agree with the
#     original on everything and prove nothing.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None
set -eu

command -v swipl >/dev/null

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT HUP INT TERM

# assertEqual throws through assert/2 ("MeTTa assertion failed"), never through
# test/3 ("is ..., should ..."), so the two reproduce different classes. The
# unclosed form is the third: the reader refuses it before anything runs.
printf '!(test 1 1)\n'        > "$probe/passes.metta"
printf '!(test 1 2)\n'        > "$probe/test_mismatch.metta"
printf '!(assertEqual 1 2)\n' > "$probe/assert_mismatch.metta"
printf '!(foo\n'              > "$probe/syntax_error.metta"

# test.sh with its ONE stdout-and-stderr capture cut back to stdout: the
# defect this lane was written against, planted so the clean result above can
# be told from a walk that sees nothing. Same shape as the planted reaches in
# tests/prolog/surface_walk.pl.
crippled="$probe/test-stdout-only.sh"
sed 's|sh run.sh "$f" 2>&1|sh run.sh "$f"|' "$project_dir/test.sh" > "$crippled"
if cmp -s "$crippled" "$project_dir/test.sh"; then
    echo "FAIL: the stdout-only copy of test.sh is identical to test.sh, so \
every check against it below proves nothing. test.sh's capture line was \
reworded; update the sed above to match it." >&2
    exit 1
fi

# Only the text AFTER "FAILURE in $f:" is the claim under test. The engine's
# own ERROR: line reaches this process's stderr regardless of the fix, since
# nothing here suppresses it, so checking the WHOLE output for the diagnostic
# would pass against the broken test.sh too; what changed is whether test.sh's
# OWN block carries it.
run_fixture() {
    runner=$1
    shape=$2
    tag=$3
    ( cd "$project_dir" && sh "$runner" "$probe/$shape.metta" ) \
        > "$probe/$tag.out" 2>&1 && rc=0 || rc=$?
    printf '%s\n' "$rc" > "$probe/$tag.rc"
    awk '/^FAILURE in /{found=1; next} found' "$probe/$tag.out" \
        > "$probe/$tag.body"
}

fail() {
    echo "FAIL: $1" >&2
    echo "----- $2 -----" >&2
    cat "$probe/$2.out" >&2
    exit 1
}

carries() {
    grep -qF -- "$2" "$probe/$1.body" ||
        fail "the FAILURE block for $1 does not name $2" "$1"
}

silent_about() {
    ! grep -qF -- "$2" "$probe/$1.body" ||
        fail "the FAILURE block for $1 carries $2, which belongs to another \
failure shape" "$1"
}

failed() {
    [ "$(cat "$probe/$1.rc")" != 0 ] ||
        fail "test.sh exited 0 for $1" "$1"
}

for shape in test_mismatch assert_mismatch syntax_error; do
    run_fixture "$project_dir/test.sh" "$shape" "$shape"
    failed "$shape"
done

# Each shape names itself and stays clear of the other two signatures, which
# is what "the suite tells them apart" means: a body that carried all three
# would exit nonzero and distinguish nothing.
carries      test_mismatch   "is 1, should 2"
carries      test_mismatch   "MeTTa test failed"
silent_about test_mismatch   "MeTTa assertion failed"
silent_about test_mismatch   "Syntax error"

carries      assert_mismatch "MeTTa assertion failed"
silent_about assert_mismatch "should"
silent_about assert_mismatch "MeTTa test failed"
silent_about assert_mismatch "Syntax error"

carries      syntax_error    "Syntax error"
silent_about syntax_error    "should"
silent_about syntax_error    "MeTTa assertion failed"

# The passing file: the is/should trace and no FAILURE block, and none of the
# compiled-goal listing that sits in the same $output. That listing is what
# test.sh's filter exists to drop, so a run reporting it would mean the filter
# stopped filtering, not that the example got noisier.
run_fixture "$project_dir/test.sh" passes passes
[ "$(cat "$probe/passes.rc")" = 0 ] ||
    fail "test.sh exited nonzero for a file whose only form passes" passes
grep -qF -- "is 1, should 1" "$probe/passes.out" ||
    fail "a passing file lost its is/should trace" passes
! grep -qF -- "prolog goal" "$probe/passes.out" ||
    fail "a passing file's report carries the engine's compiled-goal listing" \
         passes

# The planted defect. Two of the three shapes are diagnosed on stderr alone,
# so a stdout-only capture loses them entirely; the third is on stdout and
# survives, which is what proves the crippled copy still runs examples rather
# than merely failing to produce output.
for shape in test_mismatch assert_mismatch syntax_error; do
    run_fixture "$crippled" "$shape" "crippled_$shape"
    failed "crippled_$shape"
done

grep -qF -- "is 1, should 2" "$probe/crippled_test_mismatch.body" ||
    fail "the stdout-only copy lost the is/should line too, so it is broken \
rather than crippled and the two checks below prove nothing" \
         crippled_test_mismatch
! grep -qF -- "MeTTa assertion failed" "$probe/crippled_assert_mismatch.body" ||
    fail "the stdout-only copy still reports the assertion failure, so the \
2>&1 in test.sh buys nothing for this shape" crippled_assert_mismatch
# The pre-print this lane's engine-side half removed. Its return would make an
# assertEqual mismatch visible on an embedded host's stdout again, and the
# stdout-only copy is where that shows.
! grep -qF -- "Assertion failed" "$probe/crippled_assert_mismatch.body" ||
    fail "an assertEqual mismatch is writing its diagnostic to STDOUT again; \
engine/metta/runtime.pl's assert/2 must report through print_message/2" \
         crippled_assert_mismatch
! grep -qF -- "Syntax error" "$probe/crippled_syntax_error.body" ||
    fail "the stdout-only copy still reports the syntax error, so the 2>&1 in \
test.sh buys nothing for this shape" crippled_syntax_error

echo "ok: test.sh's FAILURE block tells the three failure shapes apart, and \
the stdout+stderr capture is what carries two of them"
