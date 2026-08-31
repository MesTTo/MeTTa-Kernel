#!/bin/sh
# Purpose: run the engine's own test suites, as the gate runs them.
# Assumes:
#   - swipl on PATH. This suite drives the engine directly and needs no host,
#     no janus and no Python, which is why it is the one component test.sh that
#     takes no interpreter.
# Guarantees:
#   - the gate's `plunit` lane and a developer typing `sh engine/test.sh` run
#     ONE body. Everything that makes the run trustworthy lives here: the
#     redirect that keeps swipl's exit status out of a pipeline, the working
#     directory the suites' relative paths resolve against, the choicepoint
#     scan, and the load-time error scan that catches a test which never ran.
#   - the exit status is nonzero when any suite fails, prints an error while
#     LOADING, or leaves a choicepoint.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None

set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)/..

# The suites drive Python through Janus, which follows VIRTUAL_ENV rather than
# any interpreter this script picks, so a run BY HAND has to export the same
# environment the gate does or shim.plt's 18 scalar-semantics cases fail on a
# missing module that is installed in the checkout's own virtual environment.
METTA_ROOT="$HERE"
. "$HERE/select-python.sh"

run_plunit() {
    cd "$HERE/tests/prolog" || return 1
    ok=0
    log=$(mktemp)
    out=$(mktemp)
    # Redirect to a file rather than piping to tee: a pipeline's exit status is
    # the LAST command's, so swipl failing would be masked by tee succeeding.
    #
    # The suites sit under suites/<group>/, grouped by the engine unit each
    # one tests. A suite is named by its path from tests/prolog, which stays
    # the working directory: an initialization goal resolves a relative path
    # against the working directory at RUN time, so every
    # `initialization(consult('../../engine/metta.pl'))` in a suite still
    # names the engine, and so does every path a test body builds. The LOAD
    # time directives are the other half and are file-relative, which is why
    # `:- ensure_loaded('../../../../engine/metta.pl')` sits beside them.
    for suite in suites/*/*.plt; do
        [ -e "$suite" ] || continue
        swipl -g "set_test_options([format(log)]), run_tests" \
            -t halt "$suite" -- extensions >"$out" 2>&1 || ok=1
        cat "$out"; cat "$out" >>"$log"
    done
    if grep -q "succeeded with choicepoint" "$log"; then
        echo "plunit: a test succeeded with a choicepoint:"
        grep -B1 "succeeded with choicepoint" "$log"
        ok=1
    fi
    # An error printed while a suite LOADS fails this gate, because the exit
    # code above cannot see it: `-t halt` halts 0, run_tests only reports the
    # tests that got registered, and a clause whose body raises during goal
    # expansion is dropped along with the whole term expansion that produced
    # it -- for a plunit test that is BOTH the 'unit test'/4 registration and
    # the 'unit body'/2 clause, so the test does not run, does not fail, and
    # does not appear in the count. metta.plt printed
    # `Arithmetic: `foo' is not a function` at load and reported "All 233
    # tests passed" while the intact file has 234, in both configurations the
    # lane ran then, and nothing above detected it: the two checks this gate
    # had were the exit code and the choicepoint scan.
    #
    # A grep rather than swipl's own --on-error=status, which counts the same
    # errors but ALSO arms plunit: got_messages/2 and got_message/1
    # (library/ext/plunit/plunit.pl:643-665) treat on_error==status as "fail
    # any test that emits a message it did not declare", which turns the four
    # deliberate refusals in prolog_interface.plt red [measured 2026-08-26:
    # 88 suite runs, 85 rc=0 and 3 rc=1, against 0 lines matching ^ERROR in
    # all 88 of the same runs without the flag].
    if grep -q "^ERROR" "$log"; then
        echo "plunit: a suite printed an error; a clause that fails to compile"
        echo "is dropped silently and its test never runs:"
        grep -A1 "^ERROR" "$log"
        ok=1
    fi
    rm -f "$log" "$out"
    return $ok
}

run_plunit
