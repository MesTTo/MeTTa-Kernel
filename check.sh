# Purpose: the single gate. Runs every static check, both test trees, the
#   shell suites and the Prolog checks, and reports one table. Before this
#   script the entry points were scattered (test.sh, tests/*.sh,
#   tests/regression/, extensions/python/tests/, bench.sh) and nothing ran them all,
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
#                                            codespell imports imports-selftest
#                                            jscpd prolog
#                                            ciao-grade
#                                            codec-doc leatta leatta-gate-selftest
#                                            policy-inventory
#                                            policy-inventory-selftest
#                                            refusal-grounds
#                                            refusal-grounds-selftest snippets
#                                            cumulative-syntax
#                                            cumulative-syntax-selftest
#                                            pytest gallery benchmarks instructions
#                                            scaling
#                                            memory-scale memory-scale-gate
#                                            shell examples leatta layering
#          CHECK_PY=/path/to/python   pick the interpreter
#          GATE_ONLY=1                skip the REPORT tier
# Guarantees:
#   - the runtime-derived policy inventory and its nine-case discrimination
#     selftest are GATE lanes [tested:
#     test_a_planted_closed_policy_list_is_reported_by_the_inventory_lane;
#     commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
#   - semantic refusals and the four-case planted discrimination selftest are
#     GATE lanes [tested: tests/checks/check_refusal_grounds.py,
#     tests/checks/check_refusal_grounds_selftest.py; commit=acb40f1912f131ae088083d1af29b4b283019bea].
#   - memory and scaling curves run once in REPORT-then-GATE order; GATE_ONLY
#     still takes a fresh measurement and promotes only deterministic pins
#     [tested: env CHECK_PY=../../.venv-pypetta/bin/python
#     GATE_ONLY=1 sh check.sh memory-scale-gate;
#     commit=d843bb6d17a525c36afd21cab077d63b34447535].
#   - the scaling lane gates the complexity CLASS of every declared family and
#     carries two planted negative controls that it fails without
#     [tested: test_the_planted_quadratic_fails_only_the_exponent_gate,
#     test_the_planted_constant_factor_fails_only_the_growth_gate;
#     commit=906a4057ac57a340a3544ad909e829f851f35af3].
#   - executable comments, bilingual doctests, and all six gallery programs
#     run together as a blocking lane [tested: test_a_gallery_program_runs,
#     test_the_gallery_is_exactly_the_six_ruled_programs,
#     test_translation_drift_is_rejected,
#     test_shown_output_drift_is_rejected,
#     test_answer_multisets_ignore_order_and_alpha_names_but_keep_multiplicity;
#     commit=8bfe05c3850776543ece25a85038242f10b1d841].
#   - Python import contracts block module-level core-to-satellite and
#     leaf-to-facade paths, and an adjacent scratch selftest plants
#     metta._tokens -> metta._trace and requires the same command to reject it
#     by name [tested: test_a_planted_module_level_import_is_rejected;
#     commit=350c0d9dbd3c78a4f779d6331e223e939b94c2c8].
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
METTA_CHECK_PREFIX=$(dirname "$(dirname "$PY")")
if [ -f "$METTA_CHECK_PREFIX/pyvenv.cfg" ]; then
    VIRTUAL_ENV="$METTA_CHECK_PREFIX"
    PATH="$METTA_CHECK_PREFIX/bin:$PATH"
    export VIRTUAL_ENV PATH
fi

PYDIR="$HERE/extensions/python"
WANT="$*"
FAILED=''
SUMMARY=$(mktemp "${TMPDIR:-/tmp}/metta-check.XXXXXX")
MEMORY_SCALE_DATA=$(mktemp "${TMPDIR:-/tmp}/metta-memory-scale.XXXXXX")
MEMORY_SCALE_STATUS=$(mktemp "${TMPDIR:-/tmp}/metta-memory-scale-status.XXXXXX")
trap 'rm -f "$SUMMARY" "$MEMORY_SCALE_DATA" "$MEMORY_SCALE_STATUS"' EXIT

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

# The gate does not BUILD anything any more; it asks each component to build
# itself, through the same build.sh the repository's own build.sh drives. This
# file used to compile the chapter 19 C examples and engine/reader.so inline,
# which made a script named for checking the only way to produce two artifacts,
# and put a compiler invocation in the middle of a lane list.
#
# The split each component's script draws is the deciders' one: a toolchain that
# is ABSENT exits 0 with a note, because the engine falls back to the Prolog
# reader and writer and the C examples skip, and a build that is ATTEMPTED and
# FAILS exits nonzero. Only the second is a gate failure, and for the engine's
# own units it is fatal rather than recorded: the C reader and the C writer
# gate every lane below.
#
# DISCOVERED, and every component rather than two. It used to name the engine
# and the chapter 19 examples and nothing else, so a change to a component the
# gate does not build was TESTED AGAINST A STALE ARTEFACT: the Node seat's
# TypeScript is compiled by `npm ci` through the package's prepare script and by
# extensions/node/build.sh, neither of which any lane runs, so after the
# petta-to-metta rename the pytest lane at the top of this file ran the OLD
# compiled bridge against the NEW bridge.pl and failed, while the `build` lane
# 160 lines below rebuilt it and made the NEXT run pass. A gate whose verdict
# depends on how recently someone built by hand is not a gate.
#
# The same discovery build.sh uses, and the same order, because extensions/cetta
# links against what the engine produces. Provisioning is deliberately NOT run
# here: build.sh clones the two pinned dependencies when they are absent, and a
# gate that reaches the network fails for reasons that are not the tree.
#
# Each build's output is CAPTURED and printed only when it fails. A successful
# cargo build alone emits 7,457 lines of warnings from a vendored dependency,
# which would bury the lane list under compiler noise about code this
# repository does not own; a FAILED build prints in full, because that is the
# one time the text is the answer.
for component in "$HERE/engine" \
                 "$HERE"/extensions/*/ \
                 "$HERE"/examples/ch19-*/; do
    script="${component%/}/build.sh"
    [ -f "$script" ] || continue
    name=$(printf '%s' "${component%/}" | sed "s|^$HERE/||")
    build_log=$(mktemp "${TMPDIR:-/tmp}/metta-build.XXXXXX")
    if ! sh "$script" >"$build_log" 2>&1; then
        cat "$build_log" >&2
        # The engine's own units are fatal rather than recorded: the C reader
        # and the C writer gate every lane below. Everything else degrades to a
        # slower or absent configuration its own lanes already report on.
        if [ "$name" = engine ]; then
            echo "error: engine/reader.c or engine/writer.c failed to build; the C reader and writer gate every lane" >&2
            exit 1
        fi
        echo "note: $name failed to build; its lanes report against that" >&2
    fi
done

# ---------------------------------------------------------------- GATE tier
# Correctness. These must pass on every commit.

# One boot before any concurrent lane: the engine's Quick Load Format
# artifacts generate lazily on first boot, SWI's qcompile writes each .qlf
# in place, and four pytest workers first-booting a fresh tree at once
# would race those writes. Warmed once here, every lane loads a finished
# artifact set (engine/qlf_boot.pl carries the staleness and recovery
# story). `|| true` because a boot problem belongs to the lanes, which
# report it against their own expectations rather than at a warm-up.
swipl -g halt -s "$HERE/engine/main.pl" -- extensions >/dev/null 2>&1 || true

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
        ( cd "$HERE" && sh tests/shell/test_specializer_regressions.sh )
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
run GATE shell-failure sh -c "cd '$HERE' && sh tests/shell/test_example_runner_surfaces_failures.sh"
# Written 2026-08-15 in 68cffe2, the commit that REMOVED glyph-based gating, to
# prove the runner's oracle is process status and not the assertion glyphs it
# stopped reading. It was wired into nothing: not check.sh, test.sh, bench.sh,
# checks.yml or ci.yml, so it protected the property it was written for on
# exactly zero runs [measured 2026-08-18, found independently by two agents].
# It is the negative twin of the lane above: that one proves a FAILURE reports
# its diagnostic, this one proves a failure is DETECTED at all.
run GATE shell-oracle  sh -c "cd '$HERE' && sh tests/shell/test_example_runner.sh"
# The third member of that family: the two above ask whether a failure is
# detected and reported, and this one asks whether a PASS can be destroyed
# before anyone reads it. One boot under a scrubbed locale compiles the
# engine's verdict marks to replacement characters, writes them into the
# .qlf set, and leaves every later boot serving the poison; the example
# lanes then read sixteen passing checks as absent while every source byte
# is intact.
run GATE encoding     sh -c "cd '$HERE' && sh tests/shell/test_engine_text_encoding.sh"
run GATE examples     check_examples

# The specializer's whole claim, asserted over the whole corpus rather than
# trusted: under METTA_VERIFY_SPECIALIZATIONS every specialization is run
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
    # tests/data/example_skips.txt is the one definition, read by every runner.
    # This used to carry its own seven basenames against test.sh's six, and
    # the seventh, import_error_broken.metta, never matched anything: it
    # lives under _fixtures/, which the find above excludes before any skip
    # is consulted [measured 2026-08-18].
    METTA_SKIPS=$(command grep -v '^#' tests/data/example_skips.txt | awk 'NF {print $1}')
    export METTA_SKIPS
    find examples -name '*.metta' ! -path '*_fixtures*' -print0 |
        xargs -0 -P "$(nproc 2>/dev/null || echo 4)" -I {} sh -c '
            case "
$METTA_SKIPS
" in *"
$1
"*) exit 0 ;;
            esac
            out=$(METTA_VERIFY_SPECIALIZATIONS=1 timeout 120 swipl \
                      --stack_limit=8g -q -s engine/main.pl -- "$1" extensions \
                      silent </dev/null 2>&1) || true
            case "$out" in
                *metta_specialization_disagrees*)
                    printf "%s: %s\n" "$1" "$out" | head -3 ;;
            esac' _ {} > "$found" 2>&1
    if [ -s "$found" ]; then cat "$found"; rm -f "$found"; return 1; fi
    rm -f "$found"
    return 0
}
run GATE spec-differential check_specialization_differential

# A git worktree of this repository silently runs one backend fewer than the
# checkout it was cut from: extensions/mork/mork_ffi/target/ and extensions/mork/mork_ffi/morklib.so are
# gitignored build output, and extensions/mork/extension.pl reads their absence as "this
# backend was not built" rather than as an error, which is right for a tree
# that never built it and wrong for a worktree of one that did. Every suite
# then passes while testing less. worktree.sh links them; this shows the
# difference in both directions [measured 2026-08-18: 0.21s].
run GATE worktree sh -c "cd '$HERE' && sh tests/shell/test_worktree_configuration.sh"

# build.sh itself, which nothing checked before: it had no `set -e`, resolved
# its paths against the CALLER's working directory, and ended by cloning
# faiss_ffi with no destination argument into extensions/mork/faiss_ffi, a path no
# ignore rule covers. So one run dirtied the tree and the next failed on
# "destination path already exists", and a failed cargo build still reached a
# line printing "Successfully built mork_ffi". The lane re-runs an already-built
# tree and skips when there is nothing built to re-run, so it costs a cargo
# fingerprint check rather than a compile [measured 2026-08-28: 5.0s warm].
run GATE build sh -c "cd '$HERE' && sh tests/shell/test_build_is_idempotent_and_anchored.sh"

# Three shell suites that existed and nothing here ran. They were reachable only
# from .github/workflows/ci.yml, which gates pull requests into main, so no
# branch work ever ran them -- and two had rotted away from the engine by the
# time anyone looked (2026-08-28): test_loader_concurrency asserted into
# translator_rule/1 after it became a static projection over the dynamic
# translator_rule/2, and test_git_import passed a literal `true` in the MeTTa
# result slot after the unpinned forms settled on the unit `[]`, which does not
# raise, it FAILS. That is the registration defect with its consequence
# realised: a listed lane cannot rot, an unlisted suite can, and does.
run GATE git-dependency sh -c "cd '$HERE' && sh tests/shell/test_git_dependency.sh"
run GATE git-import     sh -c "cd '$HERE' && sh tests/shell/test_git_import.sh"
run GATE loader-threads sh -c "cd '$HERE' && sh tests/shell/test_loader_concurrency.sh"

# Every component's own lanes, DISCOVERED. A component is a directory with a
# check.sh, the same rule the engine applies to a control file and build.sh
# applies to a build; adding a seat needs no edit here, which is the defect
# ai-cetta-c-constraints.md C4 filed as "a new seat is three registrations, not
# one folder".
#
# SOURCED rather than executed, deliberately. Executing them would make each
# component responsible for reporting its own status, and a driver that loses a
# child's exit code is exactly how a red lane reads green -- the pipeline hazard
# this repository already records. Sourcing keeps one `run`, one summary table
# and one exit status, and keeps every lane's text where the evidence gate can
# read it.
for component_check in "$HERE"/engine/check.sh \
                       "$HERE"/extensions/*/check.sh; do
    [ -f "$component_check" ] || continue
    . "$component_check"
done


# Undefined predicates in the engine. Nothing checked the Prolog side before
# this; SWI has had the check built in all along.
#
# Two names are known-absent at load time and are allowed:
#   mettafunc/2  asserted at runtime by process_metta_string inside
#                prolog_interop_example/0 (engine/main.pl:18). SWI's own advice
#                is `:- dynamic mettafunc/2.`, which would clear it properly.
# Anything else is a regression and fails. Shrink this list, never grow it.
# mork_test/0 used to be here too, because engine/main.pl called it by name behind
# a `mork` branch; it is seam:backend_selftest/0 now, declared multifile, so a
# process with no backend has a predicate with no clauses rather than a call to
# something absent.
#
# Run with autoload OFF, which is what makes this find a library predicate an
# engine file uses without importing. With autoload on, such a name resolves at
# the first call and the check says nothing; the no-autoload GATE below does
# catch it, but only when some example happens to reach that call, one name per
# run of a corpus that takes minutes. Cutting the engine into modules is what
# made the difference matter: engine/translator.pl's use_module(library(assoc))
# used to serve engine/metta.pl too, because both compiled into one namespace
# [measured 2026-08-22: six such names over engine/metta.pl and engine/tracer.pl
# once the modules landed, all six reported here in one 4-second run, and the
# corpus lane surfacing one of them per full pass].
#
# Runs TOKENLESS, the pure kernel, deliberately: this is the one lane that
# checks the engine with no seat loaded, and it is what found the engine
# calling two hooks only the Python bridge declared multifile
# (metta_host_transport_failure/1 and metta_host_error_reason/2), an
# existence_error in every seatless process, the wasm host included. The
# engine declares both now, beside their callers in
# engine/metta/space_hooks.pl with seam:kind/2 rows in engine/ext_points.pl,
# and this lane running tokenless is the regression gate on that: reintroduce
# an engine call to a hook only a seat declares and this reports it.
PROLOG_KNOWN_UNDEFINED='mettafunc/2'
check_prolog() {
    cd "$HERE" || return 1
    unexpected=$(
        swipl -q -g "use_module(library(check)), \
                     set_prolog_flag(autoload, false), \
                     consult('engine/main.pl'), list_undefined, halt." \
              -t 'halt(1)' 2>&1 \
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
        -t halt suites/seams/ciao_grade.plt
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
# extensions/mork/, extensions/mork/mork_ffi/ and extensions/python/metta/ with
# prolog_walk_code/1, adds a probe
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
    for suite in suites/*/*.plt; do
        [ -e "$suite" ] || continue
        # dev_typed.plt consults the engine itself; running it UNDER the
        # typed build would consult the engine twice into one session.
        [ "$suite" = suites/seams/dev_typed.plt ] && continue
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
run REPORT spec-status          "$PY" "$HERE/tests/checks/check_spec_status.py"
# Same split as evidence / prolog-reach: the report is forgiving, the proof
# that it still discriminates is not. 17 planted cases, plus a FIXED item whose
# file is deleted, confirmed OPEN, restored and confirmed FIXED again.
run GATE   spec-status-selftest "$PY" "$HERE/tests/checks/check_spec_status_selftest.py"

# Every engine decision axis is a live (policy axis knob default) row in
# &metta, joined here to the code seam that consumes it. The second lane plants
# an unowned list, all four allowed exemptions, two malformed exemptions and
# both authority-owned exclusions, so an empty report cannot pass vacuously.
run GATE policy-inventory "$PY" "$HERE/tests/checks/check_policy_inventory.py"
run GATE policy-inventory-selftest "$PY" "$HERE/tests/checks/check_policy_inventory_selftest.py"

# A semantic fence belongs to Python's data model or a named MeTTa law. The
# first lane checks the central structured ground and every owned source site;
# the second plants one omission in each mechanism so an empty scan cannot pass
# vacuously.
run GATE refusal-grounds "$PY" "$HERE/tests/checks/check_refusal_grounds.py"
run GATE refusal-grounds-selftest "$PY" "$HERE/tests/checks/check_refusal_grounds_selftest.py"

# The example corpus teaches in one order and the law says so: a file may use
# only constructs introduced at or before its own number. The introduction
# table is CHECKED IN, at tests/data/syntax_introductions.txt, because a table
# derived from the corpus makes the law true by definition; held as data, the
# same law catches a file moved earlier than the construct it needs.
#
# The first lane also carries a permanent negative control INSIDE the corpus,
# examples/ch01-getting-started/_fixtures/01-reaches-forward.metta, a chapter-1
# file using two chapter-15 and chapter-22 constructs, and fails if it stops
# catching it. The second plants eight violations, one per rule, each asserted
# against the words its own rule says, so a gate that catches the wrong thing
# for the right input cannot pass.
run GATE cumulative-syntax "$PY" "$HERE/tests/checks/check_cumulative_syntax.py"
run GATE cumulative-syntax-selftest "$PY" "$HERE/tests/checks/check_cumulative_syntax_selftest.py"

# Phase 11 moves &self's execution out of Prolog's `user` module. SWI's
# autoloader resolves a missing import ANYWAY, so a module boundary can be
# broken with every lane still green. Running the corpus with autoload off is
# how the real boundary stays visible, and it must be a LANE rather than a
# one-off, because autoload silently repairs whatever regresses.
#
# The flag cannot be set with -g: measured that `swipl -g "set_prolog_flag(
# autoload,false)" -s FILE.pl` and the reverse order both see autoload=true
# inside FILE.pl's own load-time directives, because -g goals run only after
# every -s/-l file has finished loading. Hence tests/fixtures/no_autoload_boot.pl, which
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
# register_prolog_arities/1 in lib/lib_string/lib_string.pl the lane exits 1 naming the
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
        ! -path "$HERE/examples/ch20-extending-the-engine/20-04-modules-and-the-catalog/_fixtures/imports/import_error_broken.metta" -print |
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
# Every suite runs under `extensions`, the configuration the engine ships in:
# run.sh, the packaged CLI, the Python library, the C host and the Node host
# all append it. A bare swipl invocation has an empty argv and reads no
# control file at all, which is the pure kernel, and the suites used to boot
# that; the gap hid a real failure,
# spaces_storage_modules:matching_requires_a_named_space, green here and red
# in what shipped.
#
# One run rather than two. Until the seat folders merged there were two
# configurations to cover, because the host seats loaded unconditionally and
# the native ones needed a token, so the pair differed by the backends alone.
# One token covers every seat now, and the pure kernel is not a configuration
# these suites are written against: measured 2026-08-28, all 39 suites pass
# under `-- extensions` and six fail without it -- evaluation/metta.plt,
# host/python_surface.plt, libraries/lib_tabling.plt, reader/parser.plt,
# seams/extensions.plt and spaces/spaces.plt -- every one of them because the
# Python seat's bridge is absent, which is what the pure kernel means.
# Covering both would take a per-unit `condition(metta_extension_loaded(python))`,
# plunit's own escape hatch, on those six; that is the price if the pure
# kernel ever needs suite-level coverage rather than the boot-level coverage
# seams/extensions.plt already gives it.
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

# The obligation headers are the contract a library author reads, and a
# [tested X] tag is the strongest evidence in the scheme. Thirteen of them
# named tests that had never existed in the tree's history, including some
# cited by the engine pool's Guarantees block, and nothing anywhere would have
# said so: a claim with nothing behind it reads exactly like the many that are
# real. This is the linter the scheme has always implied. It reads only, needs
# no engine, and finishes in under a second, so it runs before anything that
# can hang.
#
# It also reads the commit= half of every tag, which was unchecked until
# 2026-08-26 because a token carrying an `=` never looked like a test name.
# One citation was pinned to a full object ID sharing eight characters with a
# real commit and nothing else. WORKTREE is the lawful in-progress spelling,
# since a commit cannot contain its own object ID, so the run counts those and
# RELEASE=1 refuses them: that is the cut-time check that a release does not
# ship evidence pointing at an uncommitted worktree.
run GATE evidence   "$PY" "$HERE/tests/checks/check_evidence_tags.py"

# The evidence gate is itself a claim, so it is checked the same way. A fixture
# tree carries 17 planted citations, 8 that must be accepted and 9 that must be
# rejected, and the self-test asserts the exact line each finding lands on AND
# that nothing else is reported. Nine mutations, each disabling exactly one
# rule, were each caught with the right complaint and nothing else, which is
# what stops the fixture passing vacuously [measured 2026-08-18: 0.07s]. A
# second fixture is a real repository with one commit, carrying a live pin, a
# fabricated pin differing from it only in its tail, and a WORKTREE
# placeholder; disabling either commit rule was caught [measured 2026-08-26].
run GATE evidence-selftest "$PY" "$HERE/tests/checks/check_evidence_selftest.py"

# Every website/reference/metta-*.md page says "The entries below reproduce the
# source signatures and docstrings", and across nineteen pages that promise was
# false in 20 places by omission and 47 by a signature that had moved on: a
# reader checking MeTTa.run against the reference read a shape it had not had
# for some time. They are generated now, so the promise holds by construction
# and this asks only whether what is checked in is what the source says.
run GATE reference  "$PY" "$HERE/extensions/python/tools/reference.py"

# The MeTTa half of the same promise: metta-libraries.md reproduces each
# library's own (@doc ...) atoms, and its coverage table is the burn-down
# surface interrogate provides for the Python side.
run GATE libdoc     "$PY" "$HERE/extensions/python/tools/libdoc.py"

# The codec grammar and its conformance corpus are one authority, so CODEC.md's
# tables are generated from tests/codec/corpus.json and this asks only whether
# what is checked in is what the corpus says. Before the document existed, a new
# binding reverse-engineered shim.pl, and the two shipped codecs disagreed about
# six payloads with nothing to say which was right.
run GATE codec-doc  "$PY" "$HERE/extensions/python/tools/codecdoc.py"

# The catalog's value vocabularies and the binding's Literal types are one
# authority: metta/vocabularies.py is generated from the engine's own
# (vocabulary ...) rows, and this asks only whether what is checked in is
# what the catalog says. Before it, the annotations surface advertised six
# semirings while the engine acted on two, and nothing said which was right.
run GATE vocab-sync "$PY" "$HERE/extensions/python/tools/vocabgen.py"

# llms.txt is the file an agent reads INSTEAD of the tree, so a stale claim
# there is believed rather than checked. It had gone stale exactly that way:
# it named m.fresh_space() and m.value() after both were renamed, and
# documented metta.matching and metta.measure after both were deleted. Every
# name, path, count and vocabulary word in it is checked against the running
# engine and the real tree here, and each of those five drift classes was
# reproduced against this lane before it was wired in.
run GATE llms       "$PY" "$HERE/extensions/python/tools/llmsdoc.py"

# --------------------------------------------------------------- REPORT tier
# Known backlog. Each entry names its section in the ledger and becomes a
# GATE once that section is cleared.

# P0.26's website snippet provenance backlog is enumerated in
# website/scripts/snippet_backlog.tsv. The script reports the fixed baseline's
# remaining entries and calls anything outside it UNTRACKED, so the baseline
# cannot grow silently. Promote this lane when the remaining count reaches zero.
run REPORT snippets    "$PY" "$HERE/website/scripts/audit_snippets.py"
# The site itself renders, which nothing ran before this: three config headers
# and every page's own header claim `[tested: npm run docs:build]` and no lane
# had ever run it. The build is what decides a dead internal link, and the
# engine section leans on two VitePress features a file check cannot see -- the
# @include that publishes EXTENDING.md, KERNEL.md, CODEC.md and DEVELOPING.md
# without a second copy, and the rewrites that publish them under this site's
# own lowercase spelling while the sources keep their own names so their
# relative links resolve.
#
# It does not fetch: a gate that reaches the network fails for a reason that is
# not the tree, which is the rule the Node lanes already follow, so this says
# which step is missing and passes without it. What it CANNOT skip is the
# structure: test_every_site_include_resolves and
# test_every_site_page_is_reachable_from_the_navigation run in the pytest lane
# on every machine, node or no node.
check_docs_site() {
    site="$HERE/website"
    [ -d "$site" ] || return 0
    if ! command -v npm >/dev/null 2>&1; then
        echo "note: npm not found, the documentation site will not be built" >&2
        return 0
    fi
    if [ ! -d "$site/node_modules/vitepress" ]; then
        echo "note: run 'npm ci --prefix website', the documentation site will \
not be built without vitepress" >&2
        return 0
    fi
    npm run --prefix "$site" docs:build
}
run GATE   docs        check_docs_site
# Every source path the project ships, and clean, so this gates. It used to
# read the engine, lib and README alone, which left the docs and examples a reader
# meets first unchecked: widening it turned up 27 more spellings against the
# one in engine code. .codespellrc carries the skips and the words that only
# look wrong, and its entries are bare names because codespell prunes a walked
# directory by NAME, so a ./-prefixed skip stops matching the moment a runner
# passes explicit paths.
run GATE   codespell   sh -c "cd '$HERE' && '$PY' -m codespell_lib extensions/python/metta extensions/python/bench.py extensions/python/examples extensions/python/notebooks extensions/python/tests extensions/python/tools engine lib extensions/mork extensions/node extensions/cetta examples tests website .github *.md"
# The remaining clones are small facade, protocol, and test-fixture mirrors;
# extracting them would couple layers or hide the local contract.
run REPORT jscpd       sh -c "cd '$HERE' && npx --yes jscpd --reporters ai --format python --min-lines 8 --ignore '**/__pycache__/**' extensions/python/metta extensions/python/tests"

# -------------------------------------------------------------------- report
printf '\n================ summary ================\n'
awk -F'\t' '{ printf "%-6s %-12s %s\n", $1, $2, $3 }' "$SUMMARY"

if [ -n "$FAILED" ]; then
    printf '\nGATE FAILED:%s\n' "$FAILED"
    exit 1
fi
printf '\nall gate checks passed\n'
exit 0
