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
#                                            codec-doc petta parity-perf
#                                            policy-inventory
#                                            policy-inventory-selftest
#                                            refusal-grounds
#                                            refusal-grounds-selftest snippets
#                                            cumulative-syntax
#                                            cumulative-syntax-selftest
#                                            pytest gallery benchmarks instructions
#                                            scaling
#                                            memory-scale memory-scale-gate
#                                            shell examples layering
#                                            generated-artifacts
#                                            scratch-retention
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
#   - KERNEL.md's counts and both translator-head rosters are runtime-derived,
#     with independent planted count and omission failures [tested:
#     tests/checks/check_kernel_ledger_selftest.py; commit=d7a55be4e931732a02f2178013aed47bb9cde474].
#   - generated-artifacts selects ledger, aio-mirror and reference in the order
#     their remedies converge [tested: tests/checks/check_generated_artifact_group.py;
#     commit=7d3c883f91d1d4be055fd725463d214f6fbd1438].
#   - every lane inherits a repository-local scratch directory, and a later
#     run reclaims one left by SIGKILL without touching a concurrent run
#     [tested: scratch-retention; commit=c96093349e37cc7153f31b3dd9af10246a325301].
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None

set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/tests/checks/gate_scratch.sh"
metta_gate_scratch_open "$HERE" || exit $?
trap 'metta_gate_scratch_close' EXIT
# The interpreter, and the environment SWI's Janus bridge reads to find the
# same one. Both live in select-python.sh, sourced by every runner in the tree,
# because Janus follows VIRTUAL_ENV rather than the executable a script chose:
# an inherited environment from another tool made the shell and parity lanes
# load that tool's empty Python installation while their Python-side commands
# used $PY [measured: py_numpy resolves numpy.absolute through numpy after
# alignment; command=sh check.sh no-autoload parity; fixture=inherited MCP
# VIRTUAL_ENV with CHECK_PY auto-selected;
# commit=d90a3c9620e56e42d3a2f5982b4353da8423e873].
METTA_ROOT="$HERE"
. "$HERE/select-python.sh"
[ -n "$PY" ] || { echo "check.sh: no python found (set CHECK_PY)" >&2; exit 2; }

PYDIR="$HERE/extensions/python"
# ledger is independent; aio-mirror must precede reference because aiogen.py
# rewrites aio.py and reference.py publishes that file's docstrings.
GENERATED_ARTIFACT_LANES="ledger aio-mirror reference"
WANT="$*"
case " $WANT " in
    *" generated-artifacts "*) WANT="$WANT $GENERATED_ARTIFACT_LANES" ;;
esac
FAILED=''
SUMMARY=$(mktemp "${TMPDIR:-/tmp}/metta-check.XXXXXX")
MEMORY_SCALE_DATA=$(mktemp "${TMPDIR:-/tmp}/metta-memory-scale.XXXXXX")
MEMORY_SCALE_STATUS=$(mktemp "${TMPDIR:-/tmp}/metta-memory-scale-status.XXXXXX")
check_cleanup() {
    status=$?
    trap - EXIT
    rm -f "$SUMMARY" "$MEMORY_SCALE_DATA" "$MEMORY_SCALE_STATUS" || status=1
    metta_gate_scratch_close || status=1
    exit "$status"
}
trap check_cleanup EXIT

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
# The same discovery build.sh uses, and the same order, because extensions/cmetta
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

# Every component's own lanes, DISCOVERED. A component is a directory with a
# check.sh, the same rule the engine applies to a control file and build.sh
# applies to a build; adding a seat needs no edit here, which is the defect
# ai-cmetta-c-constraints.md C4 filed as "a new seat is three registrations, not
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

# A suite that loads engine/metta.pl reads the engine's COMPILED artifacts, and
# SWI's staleness check covers a .qlf's immediate source only. The engine's
# units are consulted by umbrellas, so engine/spaces/foreign.pl compiles into
# engine/spaces.qlf and an edit to it leaves that artifact fresh by mtime: the
# suite then passes against the previous compile. engine/qlf_boot.pl is the
# purge that defeats it, the warm-up above runs it for every lane here, and
# this gate is for the runs that do not come through here at all -- one suite
# by hand, or engine/test.sh on its own, which is how the hazard was found.
# The selftest plants a missing purge, a late one and a mismatched prefix.
run GATE qlf-freshness "$PY" "$HERE/tests/checks/check_qlf_freshness.py"
run GATE qlf-freshness-selftest "$PY" "$HERE/tests/checks/check_qlf_freshness_selftest.py"

# Conformance against the semantics arbiter. PeTTa is the arbiter, and
# tests/conformance/petta/ is upstream's example corpus beside the exact
# stdout upstream printed for each file, captured from a named commit. This
# replays every entry through this engine and diffs, which is the difference
# between "PeTTa is the oracle" as a habit and as a check.
#
# The pin is VENDORED rather than read out of a sibling checkout, so a
# neighbouring working tree cannot move this lane and CI gates on the same
# bytes a developer does.
#
# A GATE per FILE: an entry gates as soon as it agrees, and an entry recorded
# as diverging carries the difference it is allowed to have, so it cannot
# drift further without failing.
run GATE   petta        sh -c "cd '$HERE' && '$PY' tests/conformance/petta.py --gate --timeout 90 --show 12"

# Performance parity with the same upstream, over the same corpus, and the
# question the conformance lane above does not ask. instructions:u NET OF EACH
# ENGINE'S OWN BOOT, minimum of three processes: this tree loads 39,977 lines
# of engine against upstream's 1,229, so it boots in 1.04e9 instructions
# against 0.45e9, and a boot-inclusive comparison would report that constant
# on every small file instead of the work
# [measured 2026-08-30]. Subtracting it is sound here: five boots spread 40k
# on 1.05e9, far under the 500k absolute allowance.
#
# It pointed at PeTTa-base until 2026-08-30, an older upstream whose layout
# has no engine/metta.pl, so the guard inside fired and the lane passed
# without measuring anything.
run GATE   parity-perf  sh -c "cd '$HERE' && '$PY' tests/checks/check_upstream_parity.py"

# The two-runtime differential: the conformance corpus's CeTTa-routable
# fragment replays through the fork's C core (CETTA_PATH overrides the
# sibling checkout) and the shared-fragment pin must hold. Fenced classes
# skip the route loudly; divergences outside the pin report and never
# block; with the fork absent this reports that and passes, the same
# absence policy the conformance lane above follows.
run GATE   cetta         "$PY" "$HERE/tests/conformance/cetta.py" --timeout 25 --show 12

# The forward half, the fork's frozen oracle corpus, left the gate on
# 2026-08-30 (user ruling): its pins were frozen from the LeaTTa-aligned
# semantics and the engine now follows upstream PeTTa, so every moved
# answer is the alignment, not a defect. tests/conformance/cetta_corpus.py
# remains runnable by hand, and re-freezing the fork's pins from the
# PeTTa-aligned tree is what would earn the lane back.

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
# The cheat sheets against the tree and the engine they describe. llms.txt
# has always OPENED by claiming this lane, and the lane did not exist until
# 2026-09-01: the library roster drifted to 33 of 34 names behind the claim.
run GATE llms       "$PY" "$HERE/tests/checks/check_llms_names.py"
run GATE llms-selftest "$PY" "$HERE/tests/checks/check_llms_selftest.py"

# KERNEL.md's two rosters and six counts come from the running translator.
# The first lane rejects a head without a reason row and a stale row without a
# head; the second runs the production comparison over a planted bad count and
# a planted missing row, independently.
run GATE kernel-ledger "$PY" "$HERE/tests/checks/check_kernel_ledger.py"
run GATE kernel-ledger-selftest "$PY" "$HERE/tests/checks/check_kernel_ledger_selftest.py"

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

# The other half of the provenance rule. A commit cannot contain its own object
# ID, so the scheme writes the work as commit A and resolves every placeholder
# to A's ID in a provenance-only commit B. That resolution was a hand sweep
# until 2026-08-31, when one reached into twelve STRING LITERALS: the twin
# re-pin tool started writing a stale object ID into every twin it priced, and
# this lane's own neighbour stopped testing its RELEASE=1 rule because the
# self-test planted an ID where the gate tested for the word. Nothing said so,
# because a resolvable ID is exactly what the gate wants to see.
# tests/checks/pin_provenance.py is that pass, deciding per file class from
# each language's own grammar, and this lane plants one of every shape to prove
# it can tell a pin from the code that writes one.
run GATE provenance-pin-selftest "$PY" "$HERE/tests/checks/check_pin_provenance_selftest.py"

# KERNEL.md is the engine's ledger of which translator head is primitive and
# which is derived, and it requires every derived form still fused into the
# compiler to say why. The library had 110 public doors and no such ledger, so
# a door that became expressible by another could sit there indefinitely: ten
# declaration doors did, each rewriting a helper's body longhand and each
# losing the loop and the transaction that helper has, which left a stale
# `(emits &s fair)` row surviving a redeclaration [measured 2026-08-31]. The
# classification is derived from the code, so this asks only whether every
# derived door says what it buys.
run GATE ledger     "$PY" "$HERE/extensions/python/tools/ledger.py"

# AsyncMeTTa's 66 mechanical doors are generated from Space by aiogen.py, so
# the two surfaces cannot drift. Hand-written they had: 15 carried a different
# signature, 16 weakened a return type and 64 of 66 paraphrased the docstring
# they claimed to reproduce, two of them refusing at runtime what the sync door
# accepts [measured 2026-08-31].
run GATE aio-mirror "$PY" "$HERE/extensions/python/tools/aiogen.py"

# Every website/reference/metta-*.md page says "The entries below reproduce the
# source signatures and docstrings", and across nineteen pages that promise was
# false in 20 places by omission and 47 by a signature that had moved on: a
# reader checking MeTTa.run against the reference read a shape it had not had
# for some time. They are generated now, so the promise holds by construction
# and this asks only whether what is checked in is what the source says.
# Keep it after aio-mirror: reference.py reads aio.py. The adjacent
# generated-artifacts contract lane makes the dependency executable.
run GATE reference  "$PY" "$HERE/extensions/python/tools/reference.py"

run GATE generated-artifacts-selftest \
    "$PY" "$HERE/tests/checks/check_generated_artifact_group.py"

run GATE scratch-retention \
    "$PY" "$HERE/tests/checks/check_gate_scratch_selftest.py"

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

# --------------------------------------------------------------- REPORT tier
# Known backlog. Each entry names its section in the ledger and becomes a
# GATE once that section is cleared.

# P0.26's website snippet provenance backlog is enumerated in
# website/scripts/snippet_backlog.tsv. The script reports the fixed baseline's
# remaining entries and calls anything outside it UNTRACKED, so the baseline
# cannot grow silently. Promote this lane when the remaining count reaches zero.
run REPORT snippets    "$PY" "$HERE/website/scripts/audit_snippets.py"
# Python that lives OUTSIDE the Python seat. Every lint lane in
# extensions/python/check.sh runs with that directory as its root, so the
# benchmark drivers the other components grew -- engine/bench.py,
# extensions/node/benchmarks/, extensions/cmetta/benchmarks/ -- were shipping
# with no linter reaching them at all. Widening found eight real findings across
# three files, including an exception class with no Error suffix and five noqa
# directives naming rules this configuration does not enable.
#
# DISCOVERED rather than listed, the same rule the build and the component lanes
# follow: a component that grows a driver is covered without an edit here. ruff
# resolves the repository's own pyproject.toml by walking up from each file, so
# the seat's configuration decides, and the paths are literal so the evidence
# gate can model what this lane covers.
# TRACKED files, asked of git rather than walked. A walk finds vendored build
# output nothing here owns: extensions/mork/mork_ffi/target/ alone carries a
# generated jemalloc test script with five findings in it, and every ignore
# pattern that hides it is one more thing to keep true. What the repository
# tracks is the answer to what the repository is responsible for.
check_component_python() {
    found=$(cd "$HERE" && git ls-files -- 'engine/*.py' 'extensions/*/*.py' \
                'extensions/*/*/*.py' 'examples/ch19-*/*.py' |
            grep -v '^extensions/python/')
    [ -n "$found" ] || return 0
    # shellcheck disable=SC2086  -- the list is newline-separated paths this
    # tree owns, and word splitting is how they reach ruff as arguments.
    ( cd "$HERE" && "$PY" -m ruff check $found )
}
run GATE   ruff-drivers check_component_python
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
run GATE   codespell   sh -c "cd '$HERE' && '$PY' -m codespell_lib extensions/python/metta extensions/python/bench.py extensions/python/examples extensions/python/notebooks extensions/python/tests extensions/python/tools engine lib extensions/mork extensions/node extensions/cmetta examples tests website .github *.md"
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
