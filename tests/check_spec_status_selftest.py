"""Purpose: prove check_spec_status.py discriminates FIXED from OPEN from
UNKNOWN, by building a small, synthetic workspace where each verdict is
planted on purpose, running the real checker over it, and asserting the
exact result -- plus the sharpest form of the discrimination proof this
task asked for: build one item FIXED, delete the file it depends on, show
the SAME item flip to OPEN, restore the file, and show it flip back.

Running the checker on the real PyPeTTa1 workspace, as `check_spec_status.py`
does, proves the workspace's own spec reads a certain way TODAY. It says
nothing about whether the checker can tell a FIXED item from an OPEN one at
all, which is the mistake this file exists to rule out: three separate
"a bare name/file/lane existing means FIXED" heuristics were each written,
looked reasonable, and were each caught wrong by running the checker against
the REAL spec (see check_spec_status.py's own module docstring for the three
rounds). Planted fixtures catch the same class of mistake without needing
175 real items to happen to exercise it.

The tree is written from scratch under a temporary directory, laid out
exactly like this repository's own workspace -- `<T>/workspace/repo` is
ROOT, `<T>/workspace/ai-spec-execution.md` is the spec, `<T>/Sibling/` is an
arbiter-corpus-shaped sibling one level further out -- because
check_spec_status.py derives WORKSPACE and SEARCH_ROOTS from ROOT's own
position, and a fixture that collapses that nesting would not exercise the
code path that matters (P2.13's `LeaTTa/...` citation, resolved one
directory past WORKSPACE, is the reason that path exists at all). The
checker and its two sibling dependencies are copied into `repo/tools/`,
mirroring check_evidence_selftest.py's own reason for copying rather than
importing: a copy sitting under a path this checker or `check_evidence_tags`
itself scans would have its own docstring, or this file's fixture data, read
as claims about a tree it is only visiting.
Guarantees:
  - every planted FIXED, OPEN and UNKNOWN case is reported as such, and nothing
    unplanted is reported FIXED or OPEN [assumed 2026-08-18: this file's
    own main() IS the proof, run by hand since neither this file nor
    check_spec_status.py is wired into check.sh yet, single-owner]
  - the same item id reports FIXED when its file exists and is gated, OPEN
    once that exact file is removed, and FIXED again once it returns,
    across three runs of the same checker against the same tree
    [assumed 2026-08-18: same run as above]
Fails when:
  - run against a tree it did not write; it asserts exact ids, verdicts and
    reason substrings in a fixture it generates itself, like
    check_evidence_selftest.py does for check_evidence_tags.py
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent

CHECK_SH = """\
run GATE known-good sh -c "cd \\"$HERE\\" && sh tests/known_good.sh"
run GATE deep-test sh -c "cd \\"$HERE\\" && sh tests/nested/deep_test.sh"
run GATE promoted-lane echo promoted
run REPORT unpromoted-lane echo unpromoted
run GATE preexisting-lane echo preexisting
run GATE pytest sh -c "cd '$PYDIR' && '$PY' -m pytest tests -q -p no:benchmark"
run GATE plunit sh -c "cd '$HERE/tests/prolog' && for suite in *.plt; do swipl -g run_tests -t halt \\"$suite\\"; done"
run GATE shell sh -c "cd \\"$HERE\\" && sh test.sh"
"""

TEST_SH = """\
find ./examples -type f -name '*.metta' ! -path '*/_fixtures/*' -print > /tmp/fixture_filelist
SKIPS=$(grep -v '^#' tests/example_skips.txt | awk 'NF {print $1}')
while IFS= read -r f; do sh run.sh "$f" || exit 1; done < /tmp/fixture_filelist
"""

FILES = {
    ".github/workflows/checks.yml": "run: sh check.sh\n",
    ".github/workflows/ci.yml": "run: sh test.sh\n",
    "bindings/python/pyproject.toml": '[tool.pytest.ini_options]\npythonpath = ["."]\n',
    "tests/known_good.sh": "#!/bin/sh\nexit 0\n",
    "tests/nested/deep_test.sh": "#!/bin/sh\nexit 0\n",
    "tests/example_skips.txt": "# path   reason\n",
    "tests/prolog/suite.plt": (
        ":- begin_tests(fixture_unit).\n\n"
        "test(a_pinning_plunit_test) :-\n    1 =:= 1.\n\n"
        ":- end_tests(fixture_unit).\n\n"
        "coincidental_name :-\n    true.\n"
    ),
    "bindings/python/tests/test_preexisting.py": "def test_preexisting():\n    assert True\n",
    "bindings/python/tests/test_pinning.py": (
        "def test_the_specific_behavior_pins_it():\n    assert True\n"
    ),
    "engine/fixture_engine.pl": (
        "preexisting_predicate(_) :-\n    true.\n\n"
        "ok_check(X) :-\n"
        "    (   ok(X)\n"
        "    ->  true\n"
        "    ;   false\n"
        "    ).\n"
    ),
    "examples/some_example.metta": "!(+ 1 2)\n",
    "Sibling/marker.txt": "an existing sibling file, untracked by any runner\n",
}

# Fixture ids follow the real spec's own P<phase>.<n> shape (parse_items
# refuses anything else), phases 90-92 to stay out of the real document's
# range. (item_id, expected_status, expected_ambiguous, why)
CASES = [
    ("P90.1", "FIXED", False, "a file literally named in a GATE lane"),
    ("P90.2", "OPEN", False, "a file named nowhere in the tree"),
    ("P90.3", "UNKNOWN", False, "no backtick anchor at all"),
    ("P90.4", "UNKNOWN", False, "a Prolog predicate that already existed"),
    ("P90.5", "UNKNOWN", False, "a file only a blanket pytest glob discovers"),
    ("P90.6", "UNKNOWN", False, "a pre-existing lane named only in acceptance"),
    ("P90.7", "FIXED", False, "a promotable lane named in the item cell, GATE"),
    ("P90.8", "OPEN", False, "a lane named in the item cell, REPORT tier"),
    ("P90.9", "FIXED", False, "a specific pytest test name that exists and is GATE"),
    ("P90.10", "OPEN", False, "a specific pytest test name that does not exist"),
    ("P90.11", "FIXED", False, "a specific plunit test name that exists and is GATE"),
    ("P90.12", "UNKNOWN", False, "a bare word that coincidentally matches a plt fixture predicate"),
    ("P90.13", "FIXED", False, "a code span matching verbatim in implementation source"),
    ("P90.14", "UNKNOWN", False, "a code span matching nothing"),
    ("P90.15", "FIXED", False, "a bare filename resolved by basename search"),
    ("P90.16", "UNKNOWN", False, "a file one level past WORKSPACE, at the third search root"),
    ("P91.1", "UNKNOWN", True, "the spec defines this id twice with different content"),
]

SPEC = """\
# Fixture spec

| id | item | evidence | acceptance | partition |
|---|---|---|---|---|
| **P90.1** | build the known-good check | see item | `tests/known_good.sh` demonstrates it | X1 |
| **P90.2** | build the never-built check | see item | `tests/never_built.sh` demonstrates it | X1 |
| **P90.3** | make the widget faster | measured slow today | it answers quicker, no fixture named | X1 |
| **P90.4** | reuse the existing predicate | see item | `preexisting_predicate/1` already covers this case | X1 |
| **P90.5** | cover it in the fast tier's own suite | see item | `bindings/python/tests/test_preexisting.py` covers it | X1 |
| **P90.6** | tighten the confidence floor | see item | the `preexisting-lane` GATE lane already catches this | X1 |
| **P90.7** | The `promoted-lane` lane is promotable | see item | promoting it makes its files GATE | X1 |
| **P90.8** | The `unpromoted-lane` lane exists | see item | promoting it makes its files GATE | X1 |
| **P90.9** | pin the specific behaviour | see item | pinned by `test_the_specific_behavior_pins_it` | X1 |
| **P90.10** | pin a behaviour nobody wrote yet | see item | pinned by `test_this_does_not_exist_yet` | X1 |
| **P90.11** | pin it at the Prolog tier | see item | pinned by `a_pinning_plunit_test` | X1 |
| **P90.12** | rename the coincidence | see item | `coincidental_name` names the concept clearly | X1 |
| **P90.13** | guard the check | see item | the fix is `( ok(X) -> true ; false )` | X1 |
| **P90.14** | guard a different check | see item | the fix is `( nope(Y) -> yes ; no )` | X1 |
| **P90.15** | build the deep check | see item | `deep_test.sh` demonstrates it | X1 |
| **P90.16** | reference the sibling corpus | see item | `Sibling/marker.txt` already states this | X1 |
| **P91.1** | first thing entirely | see item | `tests/known_good.sh` demonstrates it | X1 |

## A second table, testing the escaped-pipe cell splitter and a 2-column
## table with no acceptance column at all.

| id | item |
|---|---|
| **P91.1** | a SECOND, different row for the same id, citing `tests/never_built.sh` instead |
| **P92.1** | a row testing `T =.. [F\\|Args]` and `\\|->`, an escaped pipe inside backticks |
"""


def build(root: Path) -> None:
    """Write one complete fixture tree under `root`, which becomes ROOT."""
    workspace = root.parent
    (workspace / "ai-spec-execution.md").write_text(SPEC, encoding="utf-8")
    for name, content in FILES.items():
        if name == "Sibling/marker.txt":
            path = workspace.parent / name
        else:
            path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    (root / "check.sh").write_text(CHECK_SH, encoding="utf-8")
    (root / "test.sh").write_text(TEST_SH, encoding="utf-8")
    (root / ".git").mkdir(exist_ok=True)

    tools = root / "tools"
    tools.mkdir(exist_ok=True)
    for module in ("check_spec_status.py", "evidence_runners.py", "check_evidence_tags.py"):
        shutil.copy(HERE / module, tools / module)


def run(root: Path) -> dict:
    """Run the copied checker against `root` and parse its --json output."""
    finished = subprocess.run(
        [sys.executable, str(root / "tools/check_spec_status.py"), "--json"],
        capture_output=True,
        text=True,
        check=False,
    )
    if finished.returncode != 0:
        raise SystemExit(
            f"the checker exited {finished.returncode} on the fixture tree:\n"
            f"stdout:\n{finished.stdout}\nstderr:\n{finished.stderr}"
        )
    try:
        return json.loads(finished.stdout)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"the checker's --json output did not parse: {exc}\n{finished.stdout}") from exc


def main() -> int:
    """Build the fixture tree(s), run the real checker, and diff its output
    against every planted case; this function's assertions ARE the test."""
    complaints: list[str] = []

    with tempfile.TemporaryDirectory() as directory:
        workspace = Path(directory) / "workspace"
        root = workspace / "repo"
        root.mkdir(parents=True)
        build(root)
        payload = run(root)

        by_id = {item["id"]: item for item in payload["items"]}
        for item_id, expected_status, expected_ambiguous, why in CASES:
            found = by_id.get(item_id)
            if found is None:
                complaints.append(f"{item_id} ({why}): missing from the checker's own output entirely")
                continue
            if found["status"] != expected_status:
                complaints.append(
                    f"{item_id} ({why}): expected {expected_status}, got {found['status']}: "
                    f"{found['reasons']}"
                )
            if found["ambiguous"] != expected_ambiguous:
                complaints.append(
                    f"{item_id} ({why}): expected ambiguous={expected_ambiguous}, "
                    f"got {found['ambiguous']}"
                )

        # P92.1 must exist at all: if the escaped-pipe cell splitter regresses
        # to a naive str.split("|"), this row's cell count stops matching its
        # 2-column header and parse_items silently drops it.
        if "P92.1" not in by_id:
            complaints.append("P92.1 (escaped `\\|` inside backticks): row dropped, cell splitter regressed")

        # P90.16 must correctly LOCATE the sibling file rather than claim it
        # is absent: this is the P2.13/LeaTTa false-negative this file guards.
        sibling_case = by_id.get("P90.16")
        if sibling_case is not None:
            joined = " ".join(sibling_case["reasons"])
            if "does not exist" in joined:
                complaints.append(
                    f"P90.16: claims the sibling file does not exist, but it does, one level "
                    f"past WORKSPACE: {sibling_case['reasons']}"
                )

        # P90.6 must correctly explain WHY a pre-existing lane doesn't count
        # (named only in acceptance), not merely land on UNKNOWN by accident.
        lane_case = by_id.get("P90.6")
        if lane_case is not None and not any(
            "item's own title cell" in r or "acceptance/evidence prose" in r for r in lane_case["reasons"]
        ):
            complaints.append(f"P90.6: UNKNOWN for the wrong reason: {lane_case['reasons']}")

        expected_rows = len(CASES) + 2  # +1 for P91.1's duplicate row, +1 for P92.1 (untracked in CASES)
        if payload["total_rows"] != expected_rows:
            complaints.append(
                f"parsed {payload['total_rows']} rows, expected {expected_rows} "
                f"({len(CASES)} cases, +1 P91.1 duplicate, +1 P92.1)"
            )
        if payload["warnings"]:
            complaints.append(
                f"{len(payload['warnings'])} malformed-row warning(s) on a fixture with none "
                f"planted, most likely the escaped-pipe cell splitter: {payload['warnings']}"
            )

    # The discrimination proof itself: P90.1 depends on tests/known_good.sh
    # existing and being GATE-run. Build the SAME tree, confirm FIXED, then
    # delete exactly that file and confirm the SAME item flips to OPEN, then
    # restore it and confirm it flips back. This is the "break the thing the
    # FIXED one depends on" demonstration, made permanent and automatic
    # rather than a one-off manual check.
    with tempfile.TemporaryDirectory() as directory:
        workspace = Path(directory) / "workspace"
        root = workspace / "repo"
        root.mkdir(parents=True)
        build(root)
        target = root / "tests/known_good.sh"

        before = run(root)
        status_before = next(i["status"] for i in before["items"] if i["id"] == "P90.1")
        if status_before != "FIXED":
            complaints.append(f"discrimination proof: P90.1 was not FIXED before breaking it ({status_before})")

        target.unlink()
        after = run(root)
        status_after = next(i["status"] for i in after["items"] if i["id"] == "P90.1")
        if status_after != "OPEN":
            complaints.append(f"discrimination proof: P90.1 did not flip to OPEN once its file was deleted ({status_after})")

        target.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        restored = run(root)
        status_restored = next(i["status"] for i in restored["items"] if i["id"] == "P90.1")
        if status_restored != "FIXED":
            complaints.append(f"discrimination proof: P90.1 did not flip back to FIXED once its file returned ({status_restored})")

    for complaint in complaints:
        print(complaint)
    print(
        f"{len(complaints)} defect(s) in the spec-status checker, "
        f"over {len(CASES)} planted cases plus the FIXED->OPEN->FIXED discrimination proof"
    )
    return 1 if complaints else 0


if __name__ == "__main__":
    sys.exit(main())
