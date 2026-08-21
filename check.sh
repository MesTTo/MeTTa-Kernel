# Purpose: the single gate. Runs every static check, both test trees, the
#   shell suites and the Prolog checks, and reports one table. Before this
#   script the entry points were scattered (test.sh, tests/*.sh,
#   tests/regression/, bindings/python/tests/, bench.sh) and nothing ran them all,
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
#                                            ciao-grade
#                                            codec-doc leatta leatta-gate-selftest
#                                            policy-inventory
#                                            policy-inventory-selftest snippets
#                                            pytest benchmarks instructions
#                                            shell examples leatta layering
#          CHECK_PY=/path/to/python   pick the interpreter
#          GATE_ONLY=1                skip the REPORT tier
# Guarantees:
#   - the runtime-derived policy inventory and its nine-case discrimination
#     selftest are GATE lanes [tested:
#     test_a_planted_closed_policy_list_is_reported_by_the_inventory_lane;
#     commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
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

# SWI's Janus bridge follows VIRTUAL_ENV, not the Python executable selected
# above. An inherited environment from another tool therefore made the shell
# and parity lanes load that tool's empty Python installation while their
# Python-side commands used $PY. Point child processes at the same interpreter
# whenever it is a virtual environment [measured: py_numpy resolves
# numpy.absolute through numpy after alignment; command=sh check.sh no-autoload
# parity; fixture=inherited MCP VIRTUAL_ENV with CHECK_PY auto-selected;
# commit=d90a3c9620e56e42d3a2f5982b4353da8423e873].
PETTA_CHECK_PREFIX=$(dirname "$(dirname "$PY")")
if [ -f "$PETTA_CHECK_PREFIX/pyvenv.cfg" ]; then
    VIRTUAL_ENV="$PETTA_CHECK_PREFIX"
    PATH="$PETTA_CHECK_PREFIX/bin:$PATH"
    export VIRTUAL_ENV PATH
fi

PYDIR="$HERE/bindings/python"
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
# the dedicated benchmark gates below own those measurements. Four workers is
# the fixed load-tested ceiling, rather than a machine-size-dependent `auto`
# expansion [tested: test_the_pytest_lane_is_deterministic_under_load_protocol;
# commit=dcfc20be4933c19140ccb5759291401d13058301].
run GATE pytest       sh -c "cd '$PYDIR' && '$PY' -m pytest tests -q -p no:benchmark -n 4 --dist loadfile --max-worker-restart=0"
run GATE benchmarks   in_py "$PY" bench.py --counter-only --keep-going
run GATE instructions in_py "$PY" -m benchmarks.check_instructions
run_example_corpus() {
    py_prefix=$(dirname "$(dirname "$PY")")
    if [ -f "$py_prefix/pyvenv.cfg" ]; then
        ( cd "$HERE" && VIRTUAL_ENV="$py_prefix" PATH="$py_prefix/bin:$PATH" sh test.sh )
    else
        ( cd "$HERE" && sh test.sh )
    fi
}

check_examples() {
    run_example_corpus &&
        ( cd "$HERE" && sh tests/regression/test_specializer_regressions.sh )
}

run GATE shell        run_example_corpus

# test.sh's own "FAILURE in $f:" block used to come from
# `grep "is " | grep " should "` over stdout alone, is/should being the one
# line a !(test A B) mismatch prints. Every other failure shape, an
# assertEqual mismatch, a syntax error, an undefined predicate, throws an
# uncaught exception the engine reports to STDERR, which test.sh never
# captured, so the block printed empty: the exit code still went nonzero and
# the shell lane above still caught it, but a human reading a red run saw
# the file name and nothing about why.
run GATE shell-failure sh -c "cd '$HERE' && sh tests/test_example_runner_surfaces_failures.sh"
# Written 2026-08-15 in 68cffe2, the commit that REMOVED glyph-based gating, to
# prove the runner's oracle is process status and not the assertion glyphs it
# stopped reading. It was wired into nothing: not check.sh, test.sh, bench.sh,
# checks.yml or ci.yml, so it protected the property it was written for on
# exactly zero runs [measured 2026-08-18, found independently by two agents].
# It is the negative twin of the lane above: that one proves a FAILURE reports
# its diagnostic, this one proves a failure is DETECTED at all.
run GATE shell-oracle  sh -c "cd '$HERE' && sh tests/regression/test_example_runner.sh"
run GATE examples     check_examples

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
                      --stack_limit=8g -q -s engine/main.pl -- "$1" backends \
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
# checkout it was cut from: backends/mork/mork_ffi/target/ and backends/mork/mork_ffi/morklib.so are
# gitignored build output, and backends/mork/decider.pl reads their absence as "this
# backend was not built" rather than as an error, which is right for a tree
# that never built it and wrong for a worktree of one that did. Every suite
# then passes while testing less. worktree.sh links them; this shows the
# difference in both directions [measured 2026-08-18: 0.21s].
run GATE worktree sh -c "cd '$HERE' && sh tests/test_worktree_configuration.sh"

# The Node binding, which is the seam's second consumer. It runs the engine in
# a WebAssembly SWI inside a Node process, so it needs neither the SWI on this
# machine nor janus, and its own suite covers the boot inventory, the codec and
# the lazy answer surface. The conformance corpus is compared against the
# Python host by bindings/python/tests/test_node_binding.py, in the pytest lane above.
#
# swipl-wasm is an npm dependency and this does not fetch it: a gate that
# reaches the network is a gate that fails for a reason that is not the tree.
# It says which step is missing instead, the same shape the C extension example
# above takes when swipl-ld is absent.
check_node_binding() {
    binding="$HERE/bindings/node"
    [ -d "$binding" ] || return 0
    if ! command -v node >/dev/null 2>&1; then
        echo "note: node not found, the Node binding suite will not run" >&2
        return 0
    fi
    if [ ! -d "$binding/node_modules/swipl-wasm" ]; then
        echo "note: run 'npm ci' in bindings/node, the Node binding suite will \
not run without swipl-wasm" >&2
        return 0
    fi
    ( cd "$binding" && node --test 'test/*.test.mjs' )
}
run GATE node-binding check_node_binding

# Undefined predicates in the engine. Nothing checked the Prolog side before
# this; SWI has had the check built in all along.
#
# Two names are known-absent at load time and are allowed:
#   mettafunc/2  asserted at runtime by process_metta_string inside
#                prolog_interop_example/0 (engine/main.pl:18). SWI's own advice
#                is `:- dynamic mettafunc/2.`, which would clear it properly.
# Anything else is a regression and fails. Shrink this list, never grow it.
# mork_test/0 used to be here too, because engine/main.pl called it by name behind
# a `mork` branch; it is metta_backend_selftest/0 now, declared multifile, so a
# process with no backend has a predicate with no clauses rather than a call to
# something absent.
PROLOG_KNOWN_UNDEFINED='mettafunc/2'
check_prolog() {
    cd "$HERE" || return 1
    unexpected=$(
        swipl -q -g "consult('engine/main.pl'), list_undefined, halt." -t 'halt(1)' 2>&1 \
            | grep -E 'which is referenced by' \
            | grep -vE "$PROLOG_KNOWN_UNDEFINED"
    )
    [ -z "$unexpected" ] && return 0
    echo "$unexpected"
    return 1
}
run GATE prolog check_prolog

# Packaged Ciao assertions stay an external development grade. The engine is
# loaded unchanged, tests/prolog/ciao_grade.pl contributes pred assertions for
# the removal and translation funnels, and rtchecks collects violations as
# assrchk/1 data. The smoke must collect none; the named planted call proves
# the collector still discriminates [tested:
# test_the_ciao_grade_collects_a_planted_assertion_violation_as_data;
# commit=dcfc20be4933c19140ccb5759291401d13058301].
check_ciao_grade() {
    cd "$HERE/tests/prolog" || return 1
    swipl -q --on-warning=status --on-error=status \
        -g "set_test_options([format(log)]), run_tests" \
        -t halt ciao_grade.plt
}
run GATE ciao-grade check_ciao_grade

# Run the four reviewed library(check) predicates plus check/0 only after a
# representative MeTTa function has been compiled. The driver also enables
# var_branches before consulting the engine, so branch-only variables fail the
# gate as SWI warnings.
check_prolog_static() {
    cd "$HERE/tests/prolog" || return 1
    swipl -q --on-warning=status --on-error=status static_checks.pl
}
run GATE prolog-static check_prolog_static

# vulture and jscpd read Python alone, and none of the SWI checks above reports
# UNREACHABILITY: a predicate defined and never called is invisible to all of
# them, across 22,791 lines of Prolog [measured 2026-08-19]. This walks every clause under engine/, lib/,
# backends/, backends/mork/mork_ffi/ and bindings/python/petta/ with prolog_walk_code/1, adds a probe
# clause per directive, and adds an edge for every goal the engine BUILDS as a
# term rather than calls, which is most of the analysis and not a refinement:
# without it the 2026-08-18 report was 206 rather than 24; the tally stands at 19 [measured 2026-08-19].
#
# REPORT, because findings are a backlog and not a break. lib-surface sat in
# this tier beside it and left it on 2026-08-21, when its queue reached zero
# [measured 2026-08-18: 1.10s].
#
# COUPLED TO PHASE 11: it hardcodes `user:` in 571 of its roots, so the module
# migration must update it in the same commit or it silently reports nothing.
check_reachability() {
    cd "$HERE/tests/prolog" || return 1
    swipl -q -g reachability_report -t 'halt(0)' reachability.pl
}
run REPORT prolog-reach check_reachability

# The report is itself a claim, so it is checked the way the evidence gate is.
# A fixture of nine planted predicates, one per door and three of them required
# to be REPORTED, is written to a temporary directory and the analysis runs over
# it a second time; the check names WHICH door stopped firing. Eleven mutations,
# each disabling exactly one root class, edge kind or scan, were each caught
# with the exact set of doors predicted and nothing else, which is what stops
# the fixture passing vacuously [measured 2026-08-18: 0.90s].
check_reachability_selftest() {
    cd "$HERE/tests/prolog" || return 1
    swipl -q --on-error=status -g reachability_selftest -t 'halt(0)' reachability.pl
}
run GATE prolog-reach-selftest check_reachability_selftest

# engine/trs.pl and engine/narrowing.pl are libraries the engine does not load, so
# the `prolog` lane's consult of engine/main.pl never reaches them. Verified both
# ways: rc=0 as shipped, rc=1 with a planted undefined call.
check_prolog_metatheory() {
    cd "$HERE/tests/prolog" || return 1
    unexpected=$(
        swipl -q -g "use_module('../../engine/trs.pl'), \
                     use_module('../../engine/narrowing.pl'), \
                     list_undefined, halt." -t 'halt(1)' 2>&1 \
            | grep -E 'which is referenced by'
    )
    [ -z "$unexpected" ] && return 0
    echo "$unexpected"
    return 1
}
run GATE prolog-metatheory check_prolog_metatheory

# The compile-time rule set's overlaps, termination and local confluence. The
# REPORT prints the whole analysis and the GATE beside it fails the run on an
# overlap that is not joined. This was report-only while the shipped set's
# termination read NOT ESTABLISHED: lib_spaces' succeedsPredicate writes two
# variables its head does not, and its registration now declares that both are
# binders of its own expansion, which moves the line to ESTABLISHED and clears
# the promotion.
run REPORT translator-confluence sh -c "cd '$HERE/tests/prolog' && swipl -q --on-error=status -g translator_confluence_report -t 'halt(0)' translator_confluence.pl"
run GATE translator-confluence-gate sh -c "cd '$HERE/tests/prolog' && swipl -q --on-error=status -g translator_confluence_gate -t 'halt(0)' translator_confluence.pl"

# The detector's own selftest: five planted rule sets, each required on the
# side its shape predicts, which is what stops "0 overlaps" from meaning the
# detector stopped detecting.
run GATE translator-confluence-selftest sh -c "cd '$HERE/tests/prolog' && swipl -q --on-error=status -g translator_confluence_selftest -t 'halt(0)' translator_confluence.pl"

# The typed development build: mavis-inserted checks live in development and
# compile to NOTHING under -O; the selftest proves both directions and the
# main lane runs every plt suite under the typed build.
check_dev_typed_selftest() {
    cd "$HERE/tests/prolog" || return 1
    swipl -q --on-error=status -g dev_typed_selftest -t 'halt(0)' dev_typed.pl || return 1
    swipl -O -q --on-error=status -g dev_typed_selftest -t 'halt(0)' dev_typed.pl
}
run GATE dev-typed-selftest check_dev_typed_selftest

check_dev_typed() {
    cd "$HERE/tests/prolog" || return 1
    ok=0
    swipl -q --on-error=status -g dev_typed_report -t 'halt(0)' dev_typed.pl || ok=1
    for suite in *.plt; do
        [ -e "$suite" ] || continue
        # dev_typed.plt consults the engine itself; running it UNDER the
        # typed build would consult the engine twice into one session.
        [ "$suite" = dev_typed.plt ] && continue
        swipl -q -g dev_typed_suites -t 'halt(0)' dev_typed.pl -- "$suite" || ok=1
    done
    return $ok
}
run GATE dev-typed check_dev_typed

# A MeTTa equation whose compiled head collides with a name the module it
# compiles into already holds does not shadow that predicate, it REPLACES it
# for the rest of the process, and nothing in the tree looked for that. Two
# shipped examples did it before Phase 11 [measured 2026-08-19 on c7126f1, both
# confirmed by running the file and re-asking SWI, not inferred]:
# invertpeanoplus.metta took user:plus/3 from imported_from(system) to a local
# definition, after which plus(1,2,X) failed instead of answering 3, and
# minimal_metta.metta did the same to user:rule/3. Every gate stayed green
# through both, because nothing that ran afterwards in those processes called
# either predicate.
#
# A GATE since Phase 11, which fixed the cause rather than the instances:
# `&self` compiles into a module of its own now, so an equation for a builtin
# name is a local shadow there exactly as it is in a named space, and neither
# of the two findings is a finding any more. Refusing the names instead would
# have forbidden 78 ordinary ones [measured 2026-08-19], which is why the
# report waited for the topology rather than for a guard.
check_engine_integrity() {
    cd "$HERE/tests/prolog" || return 1
    swipl -q --on-error=status -g engine_integrity_report -t 'halt(0)' engine_integrity.pl
}
run GATE engine-integrity check_engine_integrity

# The report is a claim, so it is checked the way the reachability report is.
# Four equations are planted, two that must be reported and two that must not,
# and the arity pair is the one that matters: MeTTa arity and Prolog arity
# differ by one, and mutating that single line takes the selftest to exit 1
# naming both planted collisions it stopped seeing [measured 2026-08-19]. The
# first version of the detector swallowed an existence error and called all 279
# files clean, which is exactly what this refuses to let happen again.
check_engine_integrity_selftest() {
    cd "$HERE/tests/prolog" || return 1
    swipl -q --on-error=status -g engine_integrity_selftest -t 'halt(0)' engine_integrity.pl
}
run GATE engine-integrity-selftest check_engine_integrity_selftest

# The execution plan carries 175 numbered items and no status column, so the
# integrator dispatched three already-completed items off it in one wave. This
# derives status by ASKING THE TREE for each item's checkable anchor.
#
# It decides 5 of 158 today, and that low number is the finding rather than a
# weak tool: 62 items name no checkable anchor at all. Three generous
# heuristics were tried and each produced CONFIDENT WRONG verdicts, all three
# recorded in the module's own docstring with the item that caught them, so
# UNKNOWN is reported wherever a guess would be needed.
run REPORT spec-status          "$PY" "$HERE/tests/check_spec_status.py"
# Same split as evidence / prolog-reach: the report is forgiving, the proof
# that it still discriminates is not. 17 planted cases, plus a FIXED item whose
# file is deleted, confirmed OPEN, restored and confirmed FIXED again.
run GATE   spec-status-selftest "$PY" "$HERE/tests/check_spec_status_selftest.py"

# Every engine decision axis is a live (policy axis knob default) row in
# &petta, joined here to the code seam that consumes it. The second lane plants
# an unowned list, all four allowed exemptions, two malformed exemptions and
# both authority-owned exclusions, so an empty report cannot pass vacuously.
run GATE policy-inventory "$PY" "$HERE/tests/check_policy_inventory.py"
run GATE policy-inventory-selftest "$PY" "$HERE/tests/check_policy_inventory_selftest.py"

# Phase 11 moves &self's execution out of Prolog's `user` module. SWI's
# autoloader resolves a missing import ANYWAY, so a module boundary can be
# broken with every lane still green. Running the corpus with autoload off is
# how the real boundary stays visible, and it must be a LANE rather than a
# one-off, because autoload silently repairs whatever regresses.
#
# The flag cannot be set with -g: measured that `swipl -g "set_prolog_flag(
# autoload,false)" -s FILE.pl` and the reverse order both see autoload=true
# inside FILE.pl's own load-time directives, because -g goals run only after
# every -s/-l file has finished loading. Hence tests/no_autoload_boot.pl, which
# run.sh boots through when NO_AUTOLOAD=1 [measured 2026-08-19: 200/200].
run GATE   no-autoload  sh -c "cd '$HERE' && NO_AUTOLOAD=1 sh test.sh"

# The same walk as the backend GATE above, over lib/ instead. It was a REPORT
# while the library tier's surface was undecided: a backend is third-party and
# arm's length by construction, a shipped library sits between that and the
# engine, and the nineteen predicates involved were not one kind of thing, so
# publishing them wholesale would have made `service` mean "whatever anyone
# happens to call". Each is decided now, one at a time, with the contract it
# promises written beside it in engine/ext_points.pl, and the queue is empty
# [measured 2026-08-21: 19 findings before, 0 after, over 438 library clauses].
#
# A GATE at zero findings has to prove it can still see, so this plants the
# same four reaches the backend gate plants, through the same prover in
# tests/prolog/surface_walk.pl, and names which door stopped firing. Verified
# by mutation rather than assumed: with one planted call to
# register_prolog_arities/1 in lib/lib_string.pl the lane exits 1 naming the
# library predicate, the engine internal and the remedy [measured 2026-08-21].
check_library_surface() {
    cd "$HERE/tests/prolog" || return 1
    swipl -q --on-error=status library_surface.pl
}
run GATE lib-surface check_library_surface

# The same question one level in: not what a LIBRARY may call in the engine but
# what one engine subsystem may call in another. Python has held this line since
# the import-linter contract went in and the Prolog half had no equivalent, so
# parser, translator, specializer, spaces, tracer and duals shared one namespace
# with no declared surfaces between them.
#
# tests/prolog/layering.pl holds the contract, one line per subsystem pair with
# what the caller wants, and the lane fails on a cross-call no line allows,
# naming caller, callee and the line to add. It fails as well on a line nothing
# needs any more, on a call into a subsystem module's non-exports, and on a
# mutual recursion between subsystems that no tangle/1 line declares: the
# engine is one large cycle today and the count is the measure of untangling it.
# The walk is tests/prolog/surface_walk.pl's, so this and the two surface gates
# cannot disagree about what a call is, and it proves its eyesight on the same
# four planted doors before reporting clean [measured 2026-08-22: 462
# cross-subsystem calls over 52 contract lines, 2 components].
check_layering() {
    cd "$HERE/tests/prolog" || return 1
    swipl -q --on-error=status -g layering_gate -t 'halt(0)' layering.pl
}
run GATE layering check_layering

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
run GATE   leatta       sh -c "cd '$HERE' && '$PY' tests/conformance/leatta.py --timeout 25 --show 12 --gate-areas-file tests/conformance/leatta_gated_areas.txt"
# The discrimination proof itself. None of LeaTTa's nine real areas is clean
# enough yet to demonstrate a promoted-area regression against real data, so
# this runs the real compare() path over a two-area fixture, one promoted and
# one not, and proves both directions plus the two hard-error paths.
run GATE   leatta-gate-selftest "$PY" "$HERE/tests/conformance/leatta_gate_selftest.py"

# The two-runtime differential: the conformance corpus's CeTTa-routable
# fragment replays through the fork's C core (CETTA_PATH overrides the
# sibling checkout) and the shared-fragment pin must hold. Fenced classes
# skip the route loudly; divergences outside the pin report and never
# block; with the fork absent this reports that and passes, the leatta
# lane's own absence policy.
run GATE   cetta        "$PY" "$HERE/tests/conformance/cetta.py" --timeout 25 --show 12

# The forward half: the fork pins this engine's whole example corpus as
# normalized oracles, and every entry replays through the CURRENT tree
# against the pin, so an engine change that moves an example's answers
# fails here with the entry named, and the remedy is a deliberate
# re-freeze in the fork with the cause recorded. Absent fork: reports
# and passes, the same policy as the lanes above.
run GATE   cetta-corpus "$PY" "$HERE/tests/conformance/cetta_corpus.py" --show 10

# The example corpus is the executable semantics documentation, and until this
# lane existed it only ever ran through the ENGINE: the examples gate below
# invokes swipl on engine/main.pl, test.sh and test_metta_examples.py shell to
# run.sh, and the plunit suites load engine/metta.pl without bindings/python/petta/shim.pl.
# So the configuration users actually ship was gated by unit tests alone, and
# defects lived there under green lanes: !(py-atom "()") answered () in the
# engine and raised out of the library, and a declared type on a Python object
# was kept in one and dropped in the other, both with a green plunit test above
# them because plunit loads the engine without the shim.
#
# REPORT rather than GATE, and the reason is written down rather than absorbed:
# it found SEVEN examples that passed in the engine and failed in the library,
# all one root: run() and load() did not register a source's function
# signatures before processing its forms the way engine/filereader.pl does, so a
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
run GATE   parity      sh -c "cd '$HERE' && '$PY' bindings/python/tools/example_parity.py"

# The obligation headers are the contract a library author reads, and a
# [tested X] tag is the strongest evidence in the scheme. Thirteen of them
# named tests that had never existed in the tree's history, including some
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
run GATE reference  "$PY" "$HERE/bindings/python/tools/reference.py"

# The MeTTa half of the same promise: metta-libraries.md reproduces each
# library's own (@doc ...) atoms, and its coverage table is the burn-down
# surface interrogate provides for the Python side.
run GATE libdoc     "$PY" "$HERE/bindings/python/tools/libdoc.py"

# The codec grammar and its conformance corpus are one authority, so CODEC.md's
# tables are generated from tests/codec/corpus.json and this asks only whether
# what is checked in is what the corpus says. Before the document existed, a new
# binding reverse-engineered shim.pl, and the two shipped codecs disagreed about
# six payloads with nothing to say which was right.
run GATE codec-doc  "$PY" "$HERE/bindings/python/tools/codecdoc.py"

# The catalog's value vocabularies and the binding's Literal types are one
# authority: petta/vocabularies.py is generated from the engine's own
# (vocabulary ...) rows, and this asks only whether what is checked in is
# what the catalog says. Before it, the annotations surface advertised six
# semirings while the engine acted on two, and nothing said which was right.
run GATE vocab-sync "$PY" "$HERE/bindings/python/tools/vocabgen.py"

# llms.txt is the file an agent reads INSTEAD of the tree, so a stale claim
# there is believed rather than checked. It had gone stale exactly that way:
# it named m.fresh_space() and m.value() after both were renamed, and
# documented petta.matching and petta.measure after both were deleted. Every
# name, path, count and vocabulary word in it is checked against the running
# engine and the real tree here, and each of those five drift classes was
# reproduced against this lane before it was wired in.
run GATE llms       "$PY" "$HERE/bindings/python/tools/llmsdoc.py"

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
# P0.26's website snippet provenance backlog is enumerated in
# website/scripts/snippet_backlog.tsv. The script reports the fixed baseline's
# remaining entries and calls anything outside it UNTRACKED, so the baseline
# cannot grow silently. Promote this lane when the remaining count reaches zero.
run REPORT snippets    "$PY" "$HERE/website/scripts/audit_snippets.py"
# Every source path the project ships, and clean, so this gates. It used to
# read the engine, lib and README alone, which left the docs and examples a reader
# meets first unchecked: widening it turned up 27 more spellings against the
# one in engine code. .codespellrc carries the skips and the words that only
# look wrong, and its entries are bare names because codespell prunes a walked
# directory by NAME, so a ./-prefixed skip stops matching the moment a runner
# passes explicit paths.
run GATE   codespell   sh -c "cd '$HERE' && '$PY' -m codespell_lib bindings/python/petta bindings/python/bench.py bindings/python/examples bindings/python/tests bindings/python/tools engine lib backends examples tests website notebooks .github *.md"
# The remaining clones are small facade, protocol, and test-fixture mirrors;
# extracting them would couple layers or hide the local contract.
run REPORT jscpd       sh -c "cd '$HERE' && npx --yes jscpd --reporters ai --format python --min-lines 8 --ignore '**/__pycache__/**,**/HE/**' bindings/python/petta bindings/python/tests"

# -------------------------------------------------------------------- report
printf '\n================ summary ================\n'
awk -F'\t' '{ printf "%-6s %-12s %s\n", $1, $2, $3 }' "$SUMMARY"

if [ -n "$FAILED" ]; then
    printf '\nGATE FAILED:%s\n' "$FAILED"
    exit 1
fi
printf '\nall gate checks passed\n'
exit 0
