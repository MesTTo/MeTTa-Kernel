# Purpose: the single gate. Runs every static check, both test trees, the
#   shell suites and the Prolog checks, and reports one table. Before this
#   script the entry points were scattered (test.sh, tests/*.sh,
#   tests/regression/, python/tests/, bench.sh) and nothing ran them all,
#   so "the entire suite passes" could not be stated from one command.
#
#   Two tiers. GATE checks must pass and a failure exits nonzero. REPORT
#   checks print their findings and never fail the run; they are the
#   burn-down surface, tracked in ai-code-organisation-and-fixes.md, and
#   each moves to GATE as its backlog clears. A REPORT tier is not a
#   softened gate: nothing here is silenced, everything is printed.
#
#   Usage: sh check.sh [name ...]     names: ruff mypy ty pylint perflint
#                                            xenon refurb vulture slotscheck
#                                            bandit deptry audit interrogate
#                                            codespell imports jscpd prolog
#                                            pytest benchmarks instructions
#                                            shell examples
#          CHECK_PY=/path/to/python   pick the interpreter
#          GATE_ONLY=1                skip the REPORT tier
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None

set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
PY=${CHECK_PY:-}
if [ -z "$PY" ]; then
    for candidate in "$HOME/Dev/.venv-pypetta/bin/python" "$HERE/.venv/bin/python" python3; do
        if command -v "$candidate" >/dev/null 2>&1; then PY="$candidate"; break; fi
    done
fi
command -v "$PY" >/dev/null 2>&1 || { echo "check.sh: no python found (set CHECK_PY)" >&2; exit 2; }

PYDIR="$HERE/python"
WANT="$*"
FAILED=''
SUMMARY=$(mktemp "${TMPDIR:-/tmp}/petta-check.XXXXXX")
trap 'rm -f "$SUMMARY"' EXIT

# run TIER NAME COMMAND...
# A GATE failure is recorded; a REPORT failure is printed and forgiven.
run() {
    tier="$1"; name="$2"; shift 2
    if [ -n "$WANT" ]; then
        case " $WANT " in *" $name "*) ;; *) return 0 ;; esac
    fi
    [ "$tier" = REPORT ] && [ "${GATE_ONLY:-}" = 1 ] && return 0

    printf '\n=== %s [%s] ===\n' "$name" "$tier"
    if "$@"; then
        status=ok
    else
        status=FAIL
        [ "$tier" = GATE ] && FAILED="$FAILED $name"
    fi
    printf '%s\t%s\t%s\n' "$tier" "$name" "$status" >> "$SUMMARY"
}

in_py() { ( cd "$PYDIR" && "$@" ); }

# ---------------------------------------------------------------- GATE tier
# Correctness. These must pass on every commit.

# Each worker is a process with its own engine. Keeping one test file whole
# preserves module fixtures, and a worker crash fails instead of being retried.
# The benchmark plugin is disabled here because it refuses parallel timing;
# the dedicated benchmark gates below own those measurements.
run GATE pytest       sh -c "cd '$PYDIR' && '$PY' -m pytest tests -q -p no:benchmark -n auto --dist loadfile --max-worker-restart=0"
run GATE benchmarks   in_py "$PY" bench.py --counter-only
run GATE instructions in_py "$PY" -m benchmarks.check_instructions
run GATE shell        sh -c "cd '$HERE' && sh test.sh"
run GATE examples sh -c "cd '$HERE' && sh tests/regression/test_specializer_regressions.sh"
run GATE packaged sh -c "cd '$HERE' && sh tests/test_packaged_cli.sh"

# Undefined predicates in the engine. Nothing checked the Prolog side before
# this; SWI has had the check built in all along.
#
# Two names are known-absent at load time and are allowed:
#   mettafunc/2  asserted at runtime by process_metta_string inside
#                prolog_interop_example/0 (src/main.pl:18). SWI's own advice
#                is `:- dynamic mettafunc/2.`, which would clear it properly.
#   mork_test/0  only defined when the mork module loads, and this check runs
#                plain swipl so neither side preloads mork.
# Anything else is a regression and fails. Shrink this list, never grow it.
PROLOG_KNOWN_UNDEFINED='mettafunc/2|mork_test/0'
check_prolog() {
    cd "$HERE" || return 1
    unexpected=$(
        swipl -q -g "consult('src/main.pl'), list_undefined, halt." -t 'halt(1)' 2>&1 \
            | grep -E 'which is referenced by' \
            | grep -vE "$PROLOG_KNOWN_UNDEFINED"
    )
    [ -z "$unexpected" ] && return 0
    echo "$unexpected"
    return 1
}
run GATE prolog check_prolog

# plunit, SWI's own unit test framework. The engine had no direct tests at
# all before tests/prolog/: every one of its 3187 Prolog lines was reached
# only through janus from Python or through a whole MeTTa example, so a
# parser or translator defect surfaced as a wrong example output with
# nothing pointing at the cause.
check_plunit() {
    cd "$HERE/tests/prolog" || return 1
    ok=0
    for suite in *.plt; do
        [ -e "$suite" ] || continue
        swipl -g "set_test_options([format(log)]), run_tests" -t halt "$suite" || ok=1
    done
    return $ok
}
run GATE plunit check_plunit

# Structural checks with a clean baseline today, so a regression is a failure.
run GATE slotscheck in_py "$PY" -m slotscheck -m petta
run GATE vulture    in_py "$PY" -m vulture
run GATE imports    in_py "$PY" -m importlinter.cli lint_imports

# --------------------------------------------------------------- REPORT tier
# Known backlog. Each entry names its section in the ledger and becomes a
# GATE once that section is cleared.

# ledger C3: 250 findings, 196 auto-fixable
run REPORT ruff        in_py "$PY" -m ruff check --statistics petta tests bench.py
# ledger C2: 65 errors in 13 files
run GATE   mypy        in_py "$PY" -m mypy
# ledger C2: 67 diagnostics, independent engine
run GATE   ty          in_py "$PY" -m ty check --python "$(dirname "$(dirname "$PY")")" petta
# ledger B6: 18 cyclic-import, 80 import-outside-toplevel
run REPORT pylint      in_py "$PY" -m pylint petta --disable=C0301,C0114,C0115,C0116,R0913,R0914,R0912,R0915,C0103 --score=n
# ledger E: 255 findings, hot in the codec
run REPORT perflint    in_py "$PY" -m pylint --load-plugins=perflint --disable=all --enable=W8201,W8202,W8204,W8205 petta --score=n
# ledger B2: rank F at 47, rank E at 35
run REPORT xenon       in_py "$PY" -m xenon petta --max-absolute B --max-modules A --max-average A
run REPORT refurb      in_py "$PY" -m refurb petta bench.py
run REPORT bandit      in_py "$PY" -m bandit -q -r petta
# ledger C4: undeclared optional extras
run REPORT deptry      in_py "$PY" -m deptry .
run REPORT audit       in_py "$PY" -m pip_audit --progress-spinner off
# ledger F: 41.9% against an 80% target
run REPORT interrogate in_py "$PY" -m interrogate petta
run REPORT codespell   sh -c "cd '$HERE' && '$PY' -m codespell_lib python/petta python/bench.py src lib README.md"
run REPORT jscpd       sh -c "cd '$HERE' && npx --yes jscpd --reporters ai --format python --min-lines 8 --ignore '**/__pycache__/**,**/HE/**' python/petta python/tests"

# -------------------------------------------------------------------- report
printf '\n================ summary ================\n'
awk -F'\t' '{ printf "%-6s %-12s %s\n", $1, $2, $3 }' "$SUMMARY"

if [ -n "$FAILED" ]; then
    printf '\nGATE FAILED:%s\n' "$FAILED"
    exit 1
fi
printf '\nall gate checks passed\n'
exit 0
