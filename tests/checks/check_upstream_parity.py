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
    [assumed: the sibling checkout is a reference copy nothing in this
    repository writes to, which this tool relies on and cannot enforce].
  - perf_event_paranoid permits instructions:u without privileges
    [source: /proc/sys/kernel/perf_event_paranoid, which reads -1 on the
    machine these numbers were taken on; a stricter value makes
    measure_instructions fail loudly rather than silently skip].
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
import os
import pathlib
import statistics
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
#The checkout this tree is aligned to, and the one
#tests/conformance/petta/ pins its answers from. It was PeTTa-base until
#2026-08-30, an older upstream in a layout that has no engine/metta.pl, so
#the existence guard below fired and this lane passed without measuring
#anything.
UPSTREAM = REPO.parent / "PeTTa-upstream"
#: The COMMITTED baseline, which lives with the other test data rather than
#: beside this script. It moved there when tests/ was put into folders by kind
#: and this constant did not follow, so the file below never existed: the
#: script took the "no baseline yet" branch on every run, rebuilt one from the
#: tree it was measuring, and compared each run against itself. The
#: cross-engine half still worked, because it compares against UPSTREAM rather
#: than against the frozen record, but the tree-drift half could not fire at
#: all -- a lane that cannot fail is not a lane. Pointing it back at the
#: committed file is what makes our_inferences a tripwire again.
BASELINE = REPO / "tests" / "data" / "upstream-parity-baseline.json"
#The drivers live under tests/fixtures/, which is where every other input
#rather than program does. They were named against HERE, tests/checks/, until
#2026-08-30: swipl cannot find a source it is given, prints one line and drops
#to its toplevel, and EXITS 0, so perf reported 123M for both "boots", every
#example came back `upstream-error`, and the lane passed having measured
#nothing.
DRIVER = REPO / "tests" / "fixtures" / "parity_driver.pl"
BOOT_DRIVER = REPO / "tests" / "fixtures" / "parity_boot.pl"
TIMEOUT = 120
RUNS = 3

INSTRUCTION_RATIO = 1.02
INSTRUCTION_ABSOLUTE = 500_000
INFERENCE_RATIO = 1.02
INFERENCE_ABSOLUTE = 200


#Janus chooses its embedded Python from VIRTUAL_ENV before any py-call. A
#direct invocation through the checks venv's own python, with an unrelated
#tool's VIRTUAL_ENV still exported, printed exactly `Janus: venv directory
#'<the inherited venv>' does not contain "<it>/lib/python3.14/site-packages"`.
#Mirror check.sh: a Python running from a venv supplies that same venv and its
#bin directory to every SWI child, for both compared engines
#[measured: PARITY-INFERENCES answered instead of a Janus venv warning,
# 2026-08-30; command=_perf over 07-torch.metta through the venv Python
# while inheriting a foreign VIRTUAL_ENV; fixture=07-torch.metta;
# commit=57f21ba9edf94bcf28cde11f938bce2c241a3709].
def _child_environment() -> dict[str, str]:
    environment = os.environ.copy()
    prefix = pathlib.Path(sys.prefix)
    if (prefix / "pyvenv.cfg").is_file():
        environment["VIRTUAL_ENV"] = str(prefix)
        existing_path = environment.get("PATH") or os.defpath
        environment["PATH"] = os.pathsep.join(
            (str(pathlib.Path(sys.executable).parent), existing_path)
        )
    return environment


CHILD_ENVIRONMENT = _child_environment()


def _perf(command: list[str]) -> tuple[int, subprocess.CompletedProcess]:
    completed = subprocess.run(
        ["perf", "stat", "-e", "instructions:u", "-x", ",", *command],
        capture_output=True,
        text=True,
        timeout=TIMEOUT,
        cwd=str(REPO),
        env=CHILD_ENVIRONMENT,
        check=False,
    )
    instructions = None
    for line in completed.stderr.splitlines():
        if ",instructions:u" in line:
            instructions = int(line.split(",")[0])
    if instructions is None:
        raise RuntimeError(f"perf reported no instruction count: {completed.stderr[-300:]}")
    return instructions, completed


#A boot that did not print BOOTED did not boot, whatever perf counted for the
#process. Requiring the marker is what turns a silent misconfiguration into a
#failure instead of a number.
def boot_cost(engine_root: pathlib.Path) -> int:
    costs = []
    for _ in range(RUNS):
        count, completed = _perf(["swipl", str(BOOT_DRIVER), str(engine_root)])
        if "BOOTED" not in completed.stdout:
            message = (
                f"the boot driver did not report BOOTED for {engine_root}: "
                f"{(completed.stderr or completed.stdout).strip()[-300:]}"
            )
            raise RuntimeError(message)
        costs.append(count)
    return min(costs)


def measure(engine_root: pathlib.Path, example: pathlib.Path, boot: int) -> dict:
    """One engine, one example: min-of-RUNS net instructions, plus the
    inference count, which must agree across the runs to count at all.
    """
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
    "examples/ch22-a-reasoner-you-can-serve/22-01-logic-programs/04-nilbc.metta": (
        "ROOT-CAUSED AND OPEN, not explained away. Argument type checking is"
        " 99.4% of this example (306,132,002 inferences against 1,866,723 with"
        " check_argument_type/3 stubbed, measured 2026-08-30), and it became so"
        " in one commit: ecb213fc on 2026-08-21 routed the typing decisions"
        " through the typing-rule registry where they had been inline"
        " comparisons, taking this file from 44,327,926 inferences to"
        " 236,070,644. Reverting that commit's engine/metta.pl hunks alone, at"
        " that commit, restores 44,328,446, so the attribution is a"
        " measurement rather than a reading of the diff."
        " The drift tripwire that would have failed the day it landed could"
        " not: BASELINE pointed at tests/checks/ while the committed baseline"
        " had moved to tests/data/, so every run rebuilt a baseline from the"
        " tree it was measuring and compared it against itself. That path is"
        " fixed, which is how this was found."
        " Three narrower fixes are IN and measured, and together they are"
        " small: the shipped-answer fast path for metta_types_match_in/3"
        " (0.8%), a bare type variable taking the candidate path as upstream's"
        " get-type does (0.2%), and guards that stop two registry walks that"
        " nothing can answer. A whole-cache ceiling on has_type_in/3 measures"
        " 16.4%, so the remaining cost is spread across the typing path rather"
        " than sitting in one predicate, and closing it is a redesign of the"
        " type-witness path against upstream's shape --"
        " `('get-type'(AV, T) *-> true ; 'get-metatype'(AV, T))`, one"
        " derivation with a metatype fallback -- rather than another guard"
    ),
    "examples/ch07-control-flow/07-05-recursion/02-fib.metta": (GUARDED_ARITHMETIC),
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
    "examples/ch05-equations-and-evaluation/05-02-changing-the-equations/04-specialize.metta": (
        "translator per-clause richness on a 250-clause specializer demo:"
        " this tree records per-equation support-graph nodes with sequence"
        " ids, arity registration, effect classification and"
        " deferred-translation bookkeeping that upstream's compiler does not"
        " perform, and the demo is nothing but clause churn (88,270,238"
        " against 48,574,121 upstream, 1.82x, 2026-08-31 rebaseline). The"
        " levers that exist are exhausted: the fuel charge, the boolean"
        " scaffolding and the rule-gate probes are compiled away, and the"
        " residue is the invalidation machinery a redefinable engine keeps"
        " so that changing an equation is O(affected) rather than"
        " O(program)."
    ),
    "examples/ch11-python-as-a-notation/07-torch.metta": (
        "python-seam richness on a workload that is mostly Python: the"
        " effect classification, receipts and source tracking this tree"
        " runs around every py crossing put it 2.07% over an engine with"
        " no such seam, 0.07% past the 2% allowance (8,327,251,946 against"
        " 7,982,385,732 upstream, 2026-08-31 rebaseline). The per-crossing"
        " constants are the same family the peano entry prices; the"
        " crossing-cost track owns removing them."
    ),
    "examples/ch19-spaces-backed-by-anything/19-03-a-builtin-in-c/01-c_extension.metta": (
        "feature-versus-absent: loading this example consult-time"
        " goal-expands the tree's OWN extension source (the arithmetic"
        " guard and effect classification over the C seat's bridge), work"
        " upstream does not do because it has no extension seam at all"
        " (87,886,158 against 52,510,511 upstream, 2026-08-31 rebaseline);"
        " the evaluation underneath is at parity."
    ),
    "examples/ch19-spaces-backed-by-anything/19-03-a-builtin-in-c/02-handle.metta": (
        "feature-versus-absent, the c_extension entry's sibling: the same"
        " consult-time goal expansion over the C seat's bridge plus the"
        " handle door's registration bookkeeping, none of which upstream"
        " performs because it has no extension seam (95,329,550 against"
        " 59,845,230 upstream, 2026-08-31 rebaseline); the evaluation"
        " underneath is at parity."
    ),
    "examples/ch20-extending-the-engine/20-02-metta-written-in-metta/02-callquoteevalreduce2.metta": (
        "meta-door richness, diffuse: quote/eval/reduce crossing costs"
        " spread over every meta operation (30,630,261 against 18,139,006"
        " upstream, 2026-08-31 rebaseline); the boundary and step doors"
        " are swapped away when idle, and what remains is the metatype"
        " bookkeeping the self-interpreter chapter exercises on every"
        " form."
    ),
    "examples/ch20-extending-the-engine/20-04-modules-and-the-catalog/_fixtures/imports/relative/root.metta": (
        "import machinery, feature-versus-absent: the receipt digests,"
        " source tracking and invalidation hooks that make a re-import"
        " O(changed) are charged on first load (151,125,044 against"
        " 145,562,645 upstream, +5.5%, 2026-08-31 rebaseline); upstream"
        " re-consults blindly and pays nothing for the capability."
    ),
    "examples/ch05-equations-and-evaluation/05-02-changing-the-equations/06-specializecyclic.metta": (DISPATCH_HOP),
    "examples/ch10-errors-and-refusals/01-he_error.metta": (METTA_IMPORT),
    "examples/ch08-data/08-01-atoms-lists-and-folds/15-roman.metta": (METTA_IMPORT),
    "examples/ch18-performance/18-02-memoisation-and-tabling/09-tabling_fib.metta": (
        "library content growth, the builin_types cause: our lib_tabling"
        " is a 66-line metta surface plus a 290-line Prolog invalidation"
        " lane against upstream's 11-line stub; the import alone measures"
        " 72.7M against upstream's 11.7M (2026-08-17), covering the whole"
        " flag"
    ),
    "examples/ch22-a-reasoner-you-can-serve/22-03-search/05-fibadd.metta": (
        "the documented ISO-error-class arithmetic guards (the +2.1%"
        " scale.metta trade), density-proportional: a source-defined fib"
        " twin shows the same +6.8% net on both engines, ~70 instructions"
        " per guarded op with four per call (measured 2026-08-17); the"
        " specializer is the future lever"
    ),
    "examples/ch22-a-reasoner-you-can-serve/22-03-search/04-matespace2.metta": (DISPATCH_HOP),
    "examples/ch18-performance/18-01-larger-workloads/03-superpose_primes.metta": (DISPATCH_HOP),
    "examples/ch22-a-reasoner-you-can-serve/22-02-weighted-answers/08-nars_direct.metta": (DISPATCH_HOP),
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
    "examples/ch22-a-reasoner-you-can-serve/22-03-search/03-matespace.metta": (DISPATCH_HOP),
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
    if not any((UPSTREAM / d / "metta.pl").exists() for d in ("engine", "src")):
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
