# Purpose: this component's own gate lanes, in the root gate's vocabulary.
# Assumes: it is SOURCED by check.sh, not executed. That is what lets it use
#   `run`, `$PY`, `$HERE` and the shared summary table, so one component's lanes
#   cannot report their own status differently from another's, and a child's
#   exit code cannot be lost on the way back up -- the hazard a driver that
#   EXECUTES its children has to solve and this one does not have.
# Guarantees: every path a lane runs is written literally. tests/checks/
#   evidence_runners.py models which files a lane covers by READING this text
#   and resolving $HERE/, so a path reached through a local variable is a path
#   the evidence gate cannot see. Its plunit collector names THIS file as the
#   runner carrying check_plunit's suite loop, which is how all 49 suites stay
#   in the executed model. The collector's anchor is that loop's own line, and
#   nothing here quotes it deliberately: a comment holding the anchor verbatim
#   would keep satisfying the drift check after the loop it models had gone.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None

# The engine: the Prolog kernel under engine/, the libraries under lib/ that
# ship with it, the example corpus that is its executable semantics, and the
# analyses that read all three. These were the last lanes in the root gate whose
# subject was not the root, and there were more of them than any component
# owned.
#
# In the root file's own order, engine-bench included, because that is the order
# the whole gate ran them in and nothing here depends on being moved. The
# analyses start from tests/prolog, where every analysis script and every suite
# resolves its relative loads; the corpus lanes start from the repository root.
# What a lane CHECKS is what decides whose it is, not the directory it starts in.

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

# The engine measured with no host in the process. Every other benchmark in
# this tree reaches the engine through the Python host, so an engine change's
# cost was only ever observed with a host's cost added to it and a reader or
# translator regression arrived diluted by whatever the harness spent around
# it. The seven cases here cover boot, both readers, the translator, selective
# and skewed matching, and reduction.
#
# It gates on INFERENCES, which are deterministic, so it needs no quiet box:
# every case read an identical count in all three samples of three consecutive
# runs at loadavg 9-11. Retired instructions ride along as the second counter
# with each row's own declared band, measured over the same region through
# perf's control descriptors; the parse case exists mostly for that counter,
# because with engine/reader.so present the reader retires almost no inferences
# and nothing else here would see it move. A machine with no perf still gates,
# on inferences alone, and says which counter it dropped.
check_engine_bench() {
    # The paths are spelled out rather than reached through a variable because
    # the evidence gate models which files a lane runs by reading this text and
    # resolves $HERE/ and not a local name. engine/bench.sh picks the
    # interpreter and runs engine/bench.py, which starts one engine/bench.pl
    # process per sample and hands the counters to the shared harness in
    # extensions/python/metta/benchmarking.py; without the literals the lane
    # covers none of them and every evidence claim written in one reads as
    # unbacked.
    #
    # engine/bench.sh exits 0 with a note naming the missing step when swipl, a
    # Python, or metta.testing is absent, and nonzero when a present toolchain
    # measures a case outside its band. A missing engine/bench-baseline.json is
    # NOT a missing toolchain: it is a committed file, so it fails here rather
    # than skipping.
    CHECK_PY="$PY" sh "$HERE/engine/bench.sh"
}
run GATE engine-bench check_engine_bench

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
# The suites, through the engine's own entry point rather than a body spelled
# here. Everything that makes the run trustworthy -- the redirect that keeps
# swipl's status out of a pipeline, the working directory the suites resolve
# against, the choicepoint scan and the load-time error scan -- lives in
# engine/test.sh so a developer running that file gets all of it.
check_plunit() {
    sh "$HERE/engine/test.sh"
}
run GATE plunit check_plunit
