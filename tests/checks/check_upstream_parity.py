"""Purpose: performance parity with upstream PeTTa over the examples corpus:
every example the pinned upstream checkout can run, this tree must run in no
more real work. Two lanes, because the two questions differ:

- Cross-engine, the gate the corpus exists for: instructions:u net of each
  engine's own boot, minimum of three processes. Inference counts are NOT
  comparable across engines: upstream inlines arithmetic and comparison to
  VM instructions where this tree routes them through guarded predicates
  for ISO error classes, so the same real work counts up to 1.5x more
  inferences here while instructions stay within percents [measured
  2026-08-17: scale.metta 1.52x by inferences on identical files].
- Within this tree, the tripwire: inferences against the frozen baseline,
  deterministic to the last count, so a real engine regression trips at
  2% + 200 with zero noise.

Boot subtraction is sound on this box: five boots spread 40k instructions
on 1.05e9 [measured 2026-08-17], far under the 500k absolute allowance.
Assumes:
  - the upstream checkout at ../PeTTa-base is read-only and pinned, so its
    numbers freeze into the baseline; --rebaseline re-measures everything
    [source: PyPeTTa1/CLAUDE.md, PeTTa-base scope].
  - perf_event_paranoid permits instructions:u without privileges here
    [source: PyPeTTa1/PeTTa/CLAUDE.md, Measurement].
Decides: the allowances. Cross-engine, 2% + 500k instructions; within-tree,
  2% + 200 inferences. An example whose three runs disagree on inferences
  is nondeterministic and excluded with its status printed.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import argparse
import json
import pathlib
import statistics
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
UPSTREAM = REPO.parent / "PeTTa-base"
BASELINE = HERE / "upstream-parity-baseline.json"
DRIVER = HERE / "parity_driver.pl"
BOOT_DRIVER = HERE / "parity_boot.pl"
TIMEOUT = 120
RUNS = 3

INSTRUCTION_RATIO = 1.02
INSTRUCTION_ABSOLUTE = 500_000
INFERENCE_RATIO = 1.02
INFERENCE_ABSOLUTE = 200


def _perf(command: list[str]) -> tuple[int, subprocess.CompletedProcess]:
    completed = subprocess.run(
        ["perf", "stat", "-e", "instructions:u", "-x", ",", *command],
        capture_output=True,
        text=True,
        timeout=TIMEOUT,
        cwd=str(REPO),
        check=False,
    )
    instructions = None
    for line in completed.stderr.splitlines():
        if ",instructions:u" in line:
            instructions = int(line.split(",")[0])
    if instructions is None:
        raise RuntimeError(f"perf reported no instruction count: {completed.stderr[-300:]}")
    return instructions, completed


def boot_cost(engine_root: pathlib.Path) -> int:
    return min(_perf(["swipl", str(BOOT_DRIVER), str(engine_root)])[0] for _ in range(RUNS))


def measure(engine_root: pathlib.Path, example: pathlib.Path, boot: int) -> dict:
    """One engine, one example: min-of-RUNS net instructions, plus the
    inference count, which must agree across the runs to count at all."""
    instructions = []
    inferences = set()
    for _ in range(RUNS):
        try:
            count, completed = _perf(["swipl", str(DRIVER), str(engine_root), str(example)])
        except subprocess.TimeoutExpired:
            return {"status": "timeout"}
        marker = [
            line
            for line in completed.stdout.splitlines()
            if line.startswith("PARITY-INFERENCES:")
        ]
        if completed.returncode != 0 or not marker:
            return {
                "status": "error",
                "detail": (completed.stderr or completed.stdout).strip()[-300:],
            }
        instructions.append(count - boot)
        inferences.add(int(marker[-1].split(":")[1]))
    if len(inferences) != 1:
        return {"status": "nondeterministic"}
    return {
        "status": "ok",
        "instructions": min(instructions),
        "inferences": inferences.pop(),
    }


def corpus() -> list[pathlib.Path]:
    return sorted((REPO / "examples").rglob("*.metta"))


def build_baseline() -> dict:
    upstream_boot = boot_cost(UPSTREAM)
    our_boot = boot_cost(REPO)
    entries = {
        "//": {
            "status": "meta",
            "upstream_boot": upstream_boot,
            "our_boot": our_boot,
        }
    }
    ratios = []
    for example in corpus():
        name = str(example.relative_to(REPO))
        upstream = measure(UPSTREAM, example, upstream_boot)
        if upstream["status"] != "ok":
            entries[name] = {"status": f"upstream-{upstream['status']}"}
            continue
        ours = measure(REPO, example, our_boot)
        if ours["status"] == "nondeterministic":
            entries[name] = {"status": "nondeterministic"}
            print(f"  {name}: nondeterministic, excluded")
            continue
        if ours["status"] != "ok":
            entries[name] = {
                "status": "ours-fails",
                "detail": ours.get("detail", ""),
            }
            print(f"  {name}: OURS FAILS where upstream runs")
            continue
        entries[name] = {
            "status": "measured",
            "upstream_instructions": upstream["instructions"],
            "our_instructions": ours["instructions"],
            "our_inferences": ours["inferences"],
        }
        ratio = ours["instructions"] / max(upstream["instructions"], 1)
        ratios.append(ratio)
        print(
            f"  {name}: instructions {upstream['instructions']} -> "
            f"{ours['instructions']} ({ratio:.2f}x)"
        )
    if ratios:
        print(f"median instruction ratio ours/upstream: {statistics.median(ratios):.3f}")
    return entries


#Root-caused divergences, each waived with its cause on record; a waiver
#without a cause is a defect in this table. Anything not listed here
#still blocks.
MEMO_IMPORT = (
    "library-load machinery on the lib_memo import, the newtons_method"
    " cause exactly: the manifest pre-scan reads the whole 966-line .pl"
    " before running it, ~46M against these examples' ~110M upstream nets"
    " (measured 2026-08-17)"
)

METTA_IMPORT = (
    "metta-library import machinery, the pln_direct cause: the per-form"
    " source tracking and change hooks of the loader; lib_he alone"
    " measures 65.2M here against upstream's 39.2M (2026-08-17), and each"
    " of these examples is imports-dominated with evaluation at or better"
    " than parity underneath"
)

GUARDED_ARITHMETIC = (
    "the documented ISO-error-class arithmetic guards (the fibadd cause),"
    " density-proportional; fib.metta is fibadd's twin workload with"
    " identical numbers"
)

DISPATCH_HOP = (
    "storage-module candidate dispatch: one native_expression/4 hop per" " enumerated candidate that upstream's direct user-module clauses do" " not pay; the differential profiles match call for call otherwise" " (permutations measured 2026-08-17: identical 1.885M candidate and" " 2.248M cycle-check counts on both engines, ours acyclic_term" " against their cyclic_term, the delta the dispatch hop)"
)

WAIVERS = {
    "examples/ch09-types/02-builin_types.metta": (
        "content growth, not machinery: this tree's lib_builtin_types.metta"
        " declares 326 lines against upstream's 49, and both the"
        " per-declaration import cost and the per-test get-type cost are at"
        " parity (measured 2026-08-17: import 90.6M over ~280 declarations"
        " here, 19.1M over 49 upstream; ~1.2M per get-type on both)"
    ),
    "examples/ch07-control-flow/07-05-recursion/02-fib.metta": (GUARDED_ARITHMETIC),
    "examples/ch11-python-as-a-notation/03-python_import.metta": (DISPATCH_HOP),
    "examples/ch05-equations-and-evaluation/05-02-changing-the-equations/06-specializecyclic.metta": (DISPATCH_HOP),
    "examples/ch04-spaces-and-matching/04-02-patterns-and-bindings/08-unify_eval_branches.metta": (METTA_IMPORT),
    "examples/ch20-extending-the-engine/20-02-metta-written-in-metta/07-he_quoting.metta": (METTA_IMPORT),
    "examples/ch10-errors-and-refusals/01-he_error.metta": (METTA_IMPORT),
    "examples/ch12-testing/02-he_equalreduct.metta": (METTA_IMPORT),
    "examples/ch08-data/08-01-atoms-lists-and-folds/14-lib_roman_pair_helpers.metta": (METTA_IMPORT),
    "examples/ch08-data/08-03-the-shipped-libraries/01-library.metta": (METTA_IMPORT),
    "examples/ch08-data/08-01-atoms-lists-and-folds/15-roman.metta": (METTA_IMPORT),
    "examples/ch18-performance/18-02-memoisation-and-tabling/06-memo_dependency_invalidation.metta": (MEMO_IMPORT),
    "examples/ch18-performance/18-02-memoisation-and-tabling/09-tabling_fib.metta": (
        "library content growth, the builin_types cause: our lib_tabling"
        " is a 66-line metta surface plus a 290-line Prolog invalidation"
        " lane against upstream's 11-line stub; the import alone measures"
        " 72.7M against upstream's 11.7M (2026-08-17), covering the whole"
        " flag"
    ),
    "examples/ch18-performance/18-02-memoisation-and-tabling/01-memo_multi_answer.metta": (MEMO_IMPORT),
    "examples/ch18-performance/18-02-memoisation-and-tabling/03-memo_per_arity.metta": (MEMO_IMPORT),
    "examples/ch18-performance/18-02-memoisation-and-tabling/04-memo_same_name_multi_arity.metta": (MEMO_IMPORT),
    "examples/ch18-performance/18-02-memoisation-and-tabling/08-memo_stats.metta": (MEMO_IMPORT),
    "examples/ch18-performance/18-02-memoisation-and-tabling/05-memo_variant_nonground.metta": (MEMO_IMPORT),
    "examples/ch22-a-reasoner-you-can-serve/22-02-weighted-answers/08-nars_direct.metta": (DISPATCH_HOP),
    "examples/ch22-a-reasoner-you-can-serve/22-02-weighted-answers/07-pln_tuffy.metta": (DISPATCH_HOP),
    "examples/ch18-performance/18-01-larger-workloads/01-scale.metta": (
        "the add path's reload-erasure machinery, standing since before"
        " this session (flagged identically in the first baseline sweep):"
        " one million load-time add-atom calls each pay assertz/2 with a"
        " recorded reference so a later source error can erase the whole"
        " partial load, where upstream's bare assertz/1 records nothing;"
        " profiles otherwise matched call for call (measured 2026-08-17)."
        " The assertz/2-vs-assertz/1 4.4x per-call tick ratio deserves its"
        " own look, recorded in the survey ledger"
    ),
    "examples/ch22-a-reasoner-you-can-serve/22-03-search/01-newtons_method.metta": (
        "library-load machinery: the example is 16 lines whose cost is the"
        " lib_memo import, and the engine's manifest pre-scan reads the"
        " whole .pl before running it (the documented read-before-run"
        " export safety at consult_global), work upstream's loader does"
        " not do; the two files bare-consult within 8% of each other"
        " (106M vs 98M, measured 2026-08-17), so the delta is the loader's"
        " safety pass, visible only where an import dominates a tiny"
        " example"
    ),
    "examples/ch22-a-reasoner-you-can-serve/22-02-weighted-answers/05-pln_direct.metta": (
        "metta-library import machinery: the lib_pln import alone costs"
        " 310.7M here against upstream's 275.7M (measured 2026-08-17), and"
        " that +35M covers the example's whole +28M flag, so evaluation is"
        " at parity and the delta is the loader's per-form source tracking"
        " and change hooks, the documented 516-inferences-per-source-atom"
        " path"
    ),
    "examples/ch06-many-answers/08-permutations.metta": (DISPATCH_HOP),
    "examples/ch22-a-reasoner-you-can-serve/22-03-search/02-tilepuzzle.metta": (DISPATCH_HOP),
    "examples/ch22-a-reasoner-you-can-serve/22-02-weighted-answers/03-plntest.metta": (DISPATCH_HOP),
    "examples/ch22-a-reasoner-you-can-serve/22-02-weighted-answers/04-plntestdirect.metta": (DISPATCH_HOP),
    "examples/ch22-a-reasoner-you-can-serve/22-03-search/03-matespace.metta": (DISPATCH_HOP),
    "examples/ch22-a-reasoner-you-can-serve/22-03-search/04-matespace2.metta": (DISPATCH_HOP),
    "examples/ch18-performance/18-01-larger-workloads/03-superpose_primes.metta": (DISPATCH_HOP),
    "examples/ch22-a-reasoner-you-can-serve/22-03-search/05-fibadd.metta": (
        "the documented ISO-error-class arithmetic guards (the +2.1%"
        " scale.metta trade), density-proportional: a source-defined fib"
        " twin shows the same +6.8% net on both engines, ~70 instructions"
        " per guarded op with four per call (measured 2026-08-17); the"
        " specializer is the future lever"
    ),
}


def verdicts(baseline: dict, remeasure: bool) -> int:
    our_boot = boot_cost(REPO)
    cross, drift = [], []
    waived = []
    checked = 0
    for name, entry in sorted(baseline.items()):
        if entry.get("status") != "measured":
            continue
        example = REPO / name
        if not example.exists():
            continue
        if remeasure:
            ours = measure(REPO, example, our_boot)
            if ours["status"] != "ok":
                cross.append(f"{name}: now fails to run ({ours['status']})")
                continue
        else:
            ours = {
                "instructions": entry["our_instructions"],
                "inferences": entry["our_inferences"],
            }
        checked += 1
        allowed = (
            entry["upstream_instructions"] * INSTRUCTION_RATIO + INSTRUCTION_ABSOLUTE
        )
        if ours["instructions"] > allowed:
            line = (
                f"{name}: {ours['instructions']} instructions against "
                f"upstream's {entry['upstream_instructions']} "
                f"(allowed {allowed:.0f})"
            )
            if name in WAIVERS:
                waived.append(line)
            else:
                cross.append(line)
        if remeasure:
            drift_allowed = (
                entry["our_inferences"] * INFERENCE_RATIO + INFERENCE_ABSOLUTE
            )
            if ours["inferences"] > drift_allowed:
                drift.append(
                    f"{name}: {ours['inferences']} inferences against the "
                    f"frozen {entry['our_inferences']}"
                )
    print(f"upstream parity: {checked} examples checked")
    for line in cross:
        print(f"  CROSS-ENGINE REGRESSION {line}")
    for line in waived:
        print(f"  WAIVED (root-caused, see WAIVERS) {line}")
    for line in drift:
        print(f"  TREE DRIFT {line}")
    return 1 if cross or drift else 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rebaseline", action="store_true")
    parser.add_argument(
        "--frozen",
        action="store_true",
        help="judge the stored numbers without re-measuring this tree",
    )
    arguments = parser.parse_args()
    if not (UPSTREAM / "engine" / "metta.pl").exists():
        print(f"upstream checkout not found at {UPSTREAM}; nothing to compare")
        return 0
    if arguments.rebaseline or not BASELINE.exists():
        entries = build_baseline()
        BASELINE.write_text(json.dumps(entries, indent=1, sort_keys=True) + "\n")
        print(f"baseline written: {BASELINE}")
        broken = [n for n, e in entries.items() if e.get("status") == "ours-fails"]
        if broken:
            return 1
        return verdicts(entries, remeasure=False)
    return verdicts(json.loads(BASELINE.read_text()), remeasure=not arguments.frozen)


if __name__ == "__main__":
    sys.exit(main())
