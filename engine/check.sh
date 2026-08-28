# Purpose: this component's own gate lanes, in the root gate's vocabulary.
# Assumes: it is SOURCED by check.sh, not executed. That is what lets it use
#   `run`, `$HERE` and the shared summary table, so one component's lanes cannot
#   report their own status differently from another's, and a child's exit code
#   cannot be lost on the way back up -- the hazard a driver that EXECUTES its
#   children has to solve and this one does not have.
# Guarantees: every path a lane runs is written literally. tests/checks/
#   evidence_runners.py models which files a lane covers by READING this text
#   and resolving $HERE/, so a path reached through a local variable is a path
#   the evidence gate cannot see.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None

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
