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
#                                            shell examples leatta
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
        # A REPORT that exits nonzero has FINDINGS, which is its working state
        # and not a break. Calling both of them FAIL made a burn-down queue
        # read like a defect in the summary, and the two need different words
        # for the summary to mean anything.
        if [ "$tier" = GATE ]; then
            status=FAIL
            FAILED="$FAILED $name"
        else
            status=findings
        fi
    fi
    printf '%s\t%s\t%s\n' "$tier" "$name" "$status" >> "$SUMMARY"
}

in_py() { ( cd "$PYDIR" && "$@" ); }

# Build the C extension example so the examples gate exercises the C tier for
# real rather than taking its skip branch. swipl-ld is part of SWI-Prolog, so
# this is available wherever the engine is, but a toolchain can still be
# missing; say so instead of letting the example quietly skip.
build_c_extension_example() {
    ext="$HERE/examples/integration/c_extension"
    [ -d "$ext" ] || return 0
    if ! command -v swipl-ld >/dev/null 2>&1; then
        echo "note: swipl-ld not found, the C extension example will skip" >&2
        return 0
    fi
    for unit in cbump handle; do
        [ -f "$ext/$unit.c" ] || continue
        ( cd "$ext" && swipl-ld -shared -o "$unit" "$unit.c" ) ||
            { echo "note: the C extension example $unit failed to build" >&2; }
    done
}
build_c_extension_example

# ---------------------------------------------------------------- GATE tier
# Correctness. These must pass on every commit.

# Each worker is a process with its own engine. Keeping one test file whole
# preserves module fixtures, and a worker crash fails instead of being retried.
# The benchmark plugin is disabled here because it refuses parallel timing;
# the dedicated benchmark gates below own those measurements.
run GATE pytest       sh -c "cd '$PYDIR' && '$PY' -m pytest tests -q -p no:benchmark -n auto --dist loadfile --max-worker-restart=0"
run GATE benchmarks   in_py "$PY" bench.py --counter-only --keep-going
run GATE instructions in_py "$PY" -m benchmarks.check_instructions
run GATE shell        sh -c "cd '$HERE' && sh test.sh"
run GATE examples sh -c "cd '$HERE' && sh tests/regression/test_specializer_regressions.sh"

# The specializer's whole claim, asserted over the whole corpus rather than
# trusted: under PETTA_VERIFY_SPECIALIZATIONS every specialization is run
# against the generic call the first time it fires and the complete answer
# lists are compared with variant equality, so a specialization that answers
# differently throws instead of being believed. This is the workspace rule
# "validate every optimisation with a differential that runs it both ways"
# made into a property of every gate run rather than a thing a test has to
# remember. It found one on its first outing: an equation whose body called
# itself with a ground higher-order argument compiled a generic clause naming
# a clone that the post-compile invalidation had just abolished, so a call
# reaching the generic path answered nothing at all.
# One engine per file, run across the cores this machine has, and skipping
# exactly what test.sh skips (interactive, optional-dependency and
# long-running examples), so the lane costs about half a minute.
check_specialization_differential() {
    cd "$HERE" || return 1
    found=$(mktemp)
    # tests/example_skips.txt is the one definition, read by every runner.
    # This used to carry its own seven basenames against test.sh's six, and
    # the seventh, import_error_broken.metta, never matched anything: it
    # lives under _fixtures/, which the find above excludes before any skip
    # is consulted [measured 2026-08-18].
    PETTA_SKIPS=$(command grep -v '^#' tests/example_skips.txt | awk 'NF {print $1}')
    export PETTA_SKIPS
    find examples -name '*.metta' ! -path '*_fixtures*' -print0 |
        xargs -0 -P "$(nproc 2>/dev/null || echo 4)" -I {} sh -c '
            case "
$PETTA_SKIPS
" in *"
$1
"*) exit 0 ;;
            esac
            out=$(PETTA_VERIFY_SPECIALIZATIONS=1 timeout 120 swipl \
                      --stack_limit=8g -q -s src/main.pl -- "$1" backends \
                      silent </dev/null 2>&1) || true
            case "$out" in
                *petta_specialization_disagrees*)
                    printf "%s: %s\n" "$1" "$out" | head -3 ;;
            esac' _ {} > "$found" 2>&1
    if [ -s "$found" ]; then cat "$found"; rm -f "$found"; return 1; fi
    rm -f "$found"
    return 0
}
run GATE spec-differential check_specialization_differential
run GATE packaged sh -c "cd '$HERE' && sh tests/test_packaged_cli.sh"

# A git worktree of this repository silently runs one backend fewer than the
# checkout it was cut from: mork_ffi/target/ and mork_ffi/morklib.so are
# gitignored build output, and backends/mork.pl reads their absence as "this
# backend was not built" rather than as an error, which is right for a tree
# that never built it and wrong for a worktree of one that did. Every suite
# then passes while testing less. worktree.sh links them; this shows the
# difference in both directions [measured 2026-08-18: 0.21s].
run GATE worktree sh -c "cd '$HERE' && sh tests/test_worktree_configuration.sh"

# Undefined predicates in the engine. Nothing checked the Prolog side before
# this; SWI has had the check built in all along.
#
# Two names are known-absent at load time and are allowed:
#   mettafunc/2  asserted at runtime by process_metta_string inside
#                prolog_interop_example/0 (src/main.pl:18). SWI's own advice
#                is `:- dynamic mettafunc/2.`, which would clear it properly.
# Anything else is a regression and fails. Shrink this list, never grow it.
# mork_test/0 used to be here too, because src/main.pl called it by name behind
# a `mork` branch; it is metta_backend_selftest/0 now, declared multifile, so a
# process with no backend has a predicate with no clauses rather than a call to
# something absent.
PROLOG_KNOWN_UNDEFINED='mettafunc/2'
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

# Run the four reviewed library(check) predicates plus check/0 only after a
# representative MeTTa function has been compiled. The driver also enables
# var_branches before consulting the engine, so branch-only variables fail the
# gate as SWI warnings.
check_prolog_static() {
    cd "$HERE/tests/prolog" || return 1
    swipl -q --on-warning=status --on-error=status static_checks.pl
}
run GATE prolog-static check_prolog_static

# The same walk as the backend GATE above, over lib/ instead, and a REPORT
# because the backend answer is settled and the library one is not. A backend
# is third-party and arm's length by construction; a shipped library sits
# somewhere between that and the engine, and roughly twenty predicates are
# involved that are not one kind of thing. Publishing them wholesale would make
# `service` mean "whatever anyone happens to call", which is worse than leaving
# them undeclared, so they are listed until each is decided. Three of them were
# already published in EXTENDING.md's prose and are declared now, which is what
# clearing an entry looks like. See ai-code-organisation-and-fixes.md.
check_library_surface() {
    cd "$HERE/tests/prolog" || return 1
    swipl -q --on-error=status library_surface.pl
}
run REPORT lib-surface check_library_surface

# Parse every example and reject any form for which the translator exposes a
# second solution. Each file gets a fresh process because translating lambdas
# and specializations intentionally registers generated predicates.
check_translation_determinism() {
    cd "$HERE/tests/prolog" || return 1
    first=$(find "$HERE/examples" -type f -name '*.metta' -print -quit)
    [ -n "$first" ] || return 1
    # This upstream loader fixture is intentionally malformed. Its parent
    # example asserts that importing it reports the source error.
    find "$HERE/examples" -type f -name '*.metta' \
        ! -path "$HERE/examples/integration/_fixtures/imports/import_error_broken.metta" -print |
    LC_ALL=C sort |
    while IFS= read -r file; do
        swipl -q --on-warning=status --on-error=status \
            translation_determinism.pl -- "$file" || exit 1
    done
}
run GATE prolog-determinism check_translation_determinism

# plunit, SWI's own unit test framework. The engine had no direct tests at
# all before tests/prolog/: every one of its 3187 Prolog lines was reached
# only through janus from Python or through a whole MeTTa example, so a
# parser or translator defect surfaced as a wrong example output with
# nothing pointing at the cause.
#
# Every suite runs in each configuration the engine ships in. A bare swipl
# invocation has an empty argv, so no backend loads and the suites booted an
# engine nothing ships: run.sh, the packaged CLI and the Python library all
# append `backends`. That gap hid a real failure,
# spaces_storage_modules:matching_requires_a_named_space, which was green here
# and red in what shipped.
# A leftover choicepoint fails this gate, not just prints. plunit has been
# detecting them all along and nothing acted on the warning, which is a free
# detector thrown away. Two of them were real defects rather than untidiness:
# reduce/3 held one on every call, and a 200,000 element map-atom through the
# dispatch path then retained 86,400,000 bytes of local stack because a choice
# point defeats last call optimisation; and parse_metta_source/2 held one whose
# retry did not offer a second parse but THREW a syntax error.
#
# A test that is legitimately nondeterministic says so with plunit's own
# [nondet] option; that is the escape hatch, and it is explicit.
check_plunit() {
    cd "$HERE/tests/prolog" || return 1
    ok=0
    log=$(mktemp)
    out=$(mktemp)
    # Redirect to a file rather than piping to tee: a pipeline's exit status is
    # the LAST command's, so swipl failing would be masked by tee succeeding.
    for suite in *.plt; do
        [ -e "$suite" ] || continue
        swipl -g "set_test_options([format(log)]), run_tests" -t halt "$suite" \
            >"$out" 2>&1 || ok=1
        cat "$out"; cat "$out" >>"$log"
        [ -d "$HERE/backends" ] || continue
        echo "--- $suite (backends) ---"
        swipl -g "set_test_options([format(log)]), run_tests" \
            -t halt "$suite" -- backends >"$out" 2>&1 || ok=1
        cat "$out"; cat "$out" >>"$log"
    done
    if grep -q "succeeded with choicepoint" "$log"; then
        echo "plunit: a test succeeded with a choicepoint:"
        grep -B1 "succeeded with choicepoint" "$log"
        ok=1
    fi
    rm -f "$log" "$out"
    return $ok
}
run GATE plunit check_plunit

# Conformance against the semantics arbiter. LeaTTa is a mechanised MeTTa whose
# tests/semantics corpus carries, in every file, the answers its interpreter
# printed verbatim and the pinned hyperon build they were checked against. This
# runs each file here and diffs the answer groups, which is the difference
# between "LeaTTa is the oracle" as a habit and as a check.
#
# REPORT, and it is the honest tier for it: the corpus covers surfaces this
# engine has never claimed, and the metatype split alone (section B35 of
# ai-metta-to-python-boundary.md) accounts for a large part of what differs. It
# becomes a GATE per AREA as each area clears, rather than all at once.
#
# It lives outside this repository, so with LeaTTa absent the script says so and
# exits 0 instead of failing a checkout that never had it.
run REPORT leatta      sh -c "cd '$HERE' && '$PY' tests/conformance/leatta.py --timeout 25 --show 12"

# The example corpus is the executable semantics documentation, and until this
# lane existed it only ever ran through the ENGINE: the examples gate below
# invokes swipl on src/main.pl, test.sh and test_metta_examples.py shell to
# run.sh, and the plunit suites load src/metta.pl without python/petta/shim.pl.
# So the configuration users actually ship was gated by unit tests alone, and
# defects lived there under green lanes: !(py-atom "()") answered () in the
# engine and raised out of the library, and a declared type on a Python object
# was kept in one and dropped in the other, both with a green plunit test above
# them because plunit loads the engine without the shim.
#
# REPORT rather than GATE, and the reason is written down rather than absorbed:
# it found SEVEN examples that passed in the engine and failed in the library,
# all one root: run() and load() did not register a source's function
# signatures before processing its forms the way src/filereader.pl does, so a
# ! naming a function defined LOWER DOWN in the same file failed there. Both
# paths share prepare_parsed_forms/1 now and all seven pass either way, so
# this is a GATE [measured 2026-08-18: 200/200 agree, verified on the merged
# tree; 199 of the 200 by both ANSWERING and examples/libraries/minimal_metta.metta
# by both failing until its two library files were committed].
#
# It reads the engine through tests/conformance/leatta_run.pl, which already
# existed to print one answer GROUP per runnable form, and compares the groups
# as VALUES rather than as text. Both matter and both were got wrong first:
# comparing flat lines could not tell !(superpose (1 2 3)) then !(+ 1 1) from
# !(superpose (1 2)) then !(superpose (3 2)), and comparing text reported the
# engine's `true` against the library's `True` on 191 of 200 files, which is
# a spelling and not an answer.
run GATE   parity      sh -c "cd '$HERE' && '$PY' python/tools/example_parity.py"

# The obligation headers are the contract a library author reads, and a
# [tested X] tag is the strongest evidence in the scheme. Thirteen of them
# named tests that had never existed in the tree's history, including three
# cited by the engine pool's Guarantees block, and nothing anywhere would have
# said so: a claim with nothing behind it reads exactly like the many that are
# real. This is the linter the scheme has always implied. It reads only, needs
# no engine, and finishes in under a second, so it runs before anything that
# can hang.
run GATE evidence   "$PY" "$HERE/tests/check_evidence_tags.py"

# The evidence gate is itself a claim, so it is checked the same way. A fixture
# tree carries 15 planted citations, 6 that must be accepted and 9 that must be
# rejected, and the self-test asserts the exact line each finding lands on AND
# that nothing else is reported. Nine mutations, each disabling exactly one
# rule, were each caught with the right complaint and nothing else, which is
# what stops the fixture passing vacuously [measured 2026-08-18: 0.07s].
run GATE evidence-selftest "$PY" "$HERE/tests/check_evidence_selftest.py"

# Every website/reference/petta-*.md page says "The entries below reproduce the
# source signatures and docstrings", and across nineteen pages that promise was
# false in 20 places by omission and 47 by a signature that had moved on: a
# reader checking MeTTa.run against the reference read a shape it had not had
# for some time. They are generated now, so the promise holds by construction
# and this asks only whether what is checked in is what the source says.
run GATE reference  "$PY" "$HERE/python/tools/reference.py"

# The MeTTa half of the same promise: metta-libraries.md reproduces each
# library's own (@doc ...) atoms, and its coverage table is the burn-down
# surface interrogate provides for the Python side.
run GATE libdoc     "$PY" "$HERE/python/tools/libdoc.py"

# llms.txt is the file an agent reads INSTEAD of the tree, so a stale claim
# there is believed rather than checked. It had gone stale exactly that way:
# it named m.fresh_space() and m.value() after both were renamed, and
# documented petta.matching and petta.measure after both were deleted. Every
# name, path, count and vocabulary word in it is checked against the running
# engine and the real tree here, and each of those five drift classes was
# reproduced against this lane before it was wired in.
run GATE llms       "$PY" "$HERE/python/tools/llmsdoc.py"

# Structural checks with a clean baseline today, so a regression is a failure.
run GATE slotscheck in_py "$PY" -m slotscheck -m petta
run GATE vulture    in_py "$PY" -m vulture
run GATE imports    in_py "$PY" -m importlinter.cli lint_imports

# --------------------------------------------------------------- REPORT tier
# Known backlog. Each entry names its section in the ledger and becomes a
# GATE once that section is cleared.

# EXTENDING.md's cost table, remeasured and held to a committed baseline. It
# was produced by a throwaway outside the repo that hardcoded an absolute path
# and was run by nobody, so one of its five rows stopped reproducing with
# nothing to say so.
#
# A REPORT until 2026-08-16, on the reasoning that these numbers compare tiers
# rather than fix a budget. That was wrong in the way that matters: a
# with_metta_module/2 fast path moved the annotated @m.define tier from 20.00
# to 22.00 and the run said nothing, and it was found by reading the table. The
# counts are exact and reproduce identically across rounds, so there is nothing
# to be tolerant of. Rebaseline deliberately with --update when a row is meant
# to move, which is the same contract the other counter gates hold.
run GATE extcost       in_py "$PY" -m benchmarks.extension_cost

# Which registered library predicates declare their determinism, and which do
# not. A leftover choice point costs its caller about twice and is invisible to
# the inference counter, and two things already catch one: plunit fails the
# gate on a test that succeeds with a choicepoint, and det/1 raises at the
# predicate's own door for anything declared. This reports the gap between
# them, a predicate no test happens to call that declares nothing.
#
# A REPORT rather than a GATE because plenty of them are correctly
# nondeterministic (get-keys answers one key per solution, the way get-atoms
# does), so a gate would demand a declaration for its own sake. The list is
# for deciding, once, which each one is.
check_determinism_coverage() {
    ( cd "$HERE/tests/prolog" && swipl -q determinism_coverage.pl )
}
run REPORT determinism check_determinism_coverage

# Two residuals remain: the CLI executes a fixed argv without a shell, and
# upstream's import-overhaul fixture owns its import grouping.
run GATE   ruff        in_py "$PY" -m ruff check petta tests bench.py
# ledger C2: 65 errors in 13 files
run GATE   mypy        in_py "$PY" -m mypy
# ledger C2: 67 diagnostics, independent engine
run GATE   ty          in_py "$PY" -m ty check --python "$(dirname "$(dirname "$PY")")" petta
# Residual Pylint findings describe deliberate facades, compiler mixins,
# resource cleanup catches, and public compatibility surfaces.
run GATE   pylint      in_py "$PY" -m pylint petta --score=n
# Perflint remains a measured queue. A suggestion moves only after the exact
# instruction counter proves a win; the first attractive rewrite regressed.
#
# Where the queue stands, 2026-08-17, so its FAIL is a state and not a backlog.
# 296 findings: 217 loop-invariant-statement, which flags expressions whose
# CALLEE is invariant while the argument varies, so isinstance(child, seq) in
# the codec reads as hoistable and is not; and 79 loop-global-usage and
# dotted-import-in-loop, every one of them in import-time, plugin-discovery,
# @m.define compile-time or benchmarking code. The hot paths the benchmark
# suite actually measures report ZERO of the latter two, because the hoists
# are already there and carry their measurement: _atom_wire.py binds
# wire_sym, gnd and seq before its loop.
#
# One finding sits on a per-call path, _rebox looked up per yield in
# dispatch_raw_many. Hoisting it was measured on a workload that is nothing
# but raw generator yields, 1.2M of them, min of 3:
# 20,329,291,854 to 20,307,302,649 instructions:u, -0.108%. Not taken: a
# tenth of a percent in the most favourable case buys less than the line costs
# a reader, and 79 of them in cold code buys nothing at all.
run REPORT perflint    in_py "$PY" -m pylint --load-plugins=perflint --disable=all --enable=W8201,W8202,W8204,W8205 petta --score=n
# Complexity is REPORTED, not gated, by the user's ruling 2026-08-18. It was a
# GATE at max-absolute C, which measurement shows sat exactly on the tree's own
# ceiling: 1,669 blocks are 1,456 rank A, 200 rank B and 13 rank C, average A
# at 2.83, with nothing at D or worse. So one new rank-C block passed and one
# rank-D block failed the build, on a codebase whose interpreter dispatch is
# inherently branchy and whose next phases rewrite exactly those files.
#
# A per-block ceiling gates the wrong thing here. The signal worth keeping is a
# slide across a whole MODULE or the package AVERAGE, so those stay at A and
# still print; max-absolute moves to D so a single hairy function does not
# shout. Nothing is silenced: a REPORT prints everything it finds.
run REPORT xenon       in_py "$PY" -m xenon petta --max-absolute D --max-modules A --max-average A
# Refurb's residual type-normalization and clarity rewrites are not semantic
# equivalents at the package boundaries they flag.
run GATE   refurb      in_py "$PY" -m refurb petta bench.py
# Both Bandit findings are the fixed swipl argv call with shell mode disabled.
run GATE   bandit      in_py "$PY" -m bandit -q -c pyproject.toml -r petta
# These packages enter through deliberate lazy imports, which deptry cannot
# observe statically; each one is declared in its matching extra.
run GATE   deptry      in_py "$PY" -m deptry .
run GATE   audit       in_py "$PY" -m pip_audit --progress-spinner off
# ledger F: public API documentation is held above the 80% target
run GATE   interrogate in_py "$PY" -m interrogate petta
# Every source path the project ships, and clean, so this gates. It used to
# read src, lib and README alone, which left the docs and examples a reader
# meets first unchecked: widening it turned up 27 more spellings against the
# one in engine code. .codespellrc carries the skips and the words that only
# look wrong, and its entries are bare names because codespell prunes a walked
# directory by NAME, so a ./-prefixed skip stops matching the moment a runner
# passes explicit paths.
run GATE   codespell   sh -c "cd '$HERE' && '$PY' -m codespell_lib python/petta python/bench.py python/examples python/tests src lib backends examples tests website notebooks mork_ffi *.md"
# The remaining clones are small facade, protocol, and test-fixture mirrors;
# extracting them would couple layers or hide the local contract.
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
