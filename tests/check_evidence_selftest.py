"""Purpose: prove check_evidence_tags.py catches the things it claims to, by
building a small tree where each of them is planted on purpose and running the
real checker over it.

Running the checker on THIS repository proves the repository is clean. It says
nothing about whether the checker can see a violation, which is the same
mistake the checker exists to catch: engine/translator.pl cited a benchmark that
runs nowhere, and the citation looked exactly like the two hundred good ones
above it. So the guarantees in check_evidence_tags.py's own header are tested
here, against planted violations, and not by the gate run that finds nothing.

The tree is written from scratch each time under a temporary directory: a
check.sh with both tiers, a test.sh with the example corpus, one plunit suite,
one gate script, one example, one collected pytest module, and the orphans and
mutes that are supposed to be rejected. The checker is copied into <tree>/tools
rather than <tree>/tests, because its own SOURCES reads tests/*.py and a copy
sitting there would have its docstring read as claims about a tree it is only
visiting.

Every citation is built from a TAG variable instead of being written out. A
literal one in this file is a claim about THIS repository as far as the gate is
concerned, and the fixtures are deliberately unbacked.
Guarantees:
  - a planted citation of each rejected kind produces exactly one finding on
    its own line, and none of the accepted kinds produces any
    [tested 2026-08-18: tests/check_evidence_selftest.py]
  - a collector whose anchor has left the runner is reported
    [tested 2026-08-18: tests/check_evidence_selftest.py]
  - a gate command is accepted when check.sh runs the lane it names and
    reported when it does not, which is the second half of the scheme's
    "test name or exact gate command" and the form llms.txt's checker uses
    [tested 2026-08-22: tests/check_evidence_selftest.py]
Fails when:
  - run against a tree it did not write. It asserts exact line numbers in a
    fixture it generates, and nothing else.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
TAG = "tested"
WHEN = "2026-08-18"

# (accepted, what the citation names, why it is written this way)
CITATIONS = (
    (True, "a_plunit_test", "a plunit test in a suite the plunit lane globs"),
    (True, "test_collected", "a pytest function in a module the pytest lane collects"),
    (True, "kept", "an example test.sh runs, holding a test form"),
    (True, "checked_thing", "a predicate the gate script's entry goal reaches"),
    (True, "tests/prolog/gate_script.pl", "a gate script cited whole"),
    (True, "tests/checked.py", "a Python gate script cited whole, run by a GATE lane"),
    (False, "tests/orphan/orphan_check.pl", "a script that can fail and that nothing runs"),
    (False, "tests/orphan/mute.pl", "a script a lane runs that has no way to fail"),
    (False, "tests/printer.py", "a Python script a lane runs that only prints"),
    (False, "quiet", "an example test.sh runs that holds no test form"),
    (False, "tests/orphan/reported.pl", "a script only a REPORT lane runs"),
    (False, "test_uncollected", "a pytest function in a module pytest does not collect"),
    (True, "loaded_check", "a predicate in a file the gate script loads, which has no entry"),
    (False, "skipped", "an example holding a test form that the skip list drops"),
    (False, "no_such_thing_at_all", "a name the tree does not define"),
    (True, "GATE_ONLY=1 sh check.sh plunit",
     "an exact gate command naming a lane check.sh runs, which the "
     "obligation-header scheme accepts beside a test name"),
    (False, "GATE_ONLY=1 sh check.sh no-such-lane",
     "a gate command naming a lane check.sh does not run"),
)

CHECK_SH = """\
run() {{ :; }}
in_py() {{ ( cd "$PYDIR" && "$@" ); }}

check_plunit() {{
    cd "$HERE/tests/prolog" || return 1
    for suite in *.plt; do
        swipl -g "run_tests" -t halt "$suite" || return 1
    done
}}
run GATE plunit check_plunit
run GATE pytest sh -c "cd '$PYDIR' && '$PY' -m {pytest_anchor} -n auto"
run GATE shell sh -c "cd '$HERE' && sh test.sh"
run GATE gate-script sh -c "cd '$HERE/tests/prolog' && swipl gate_script.pl"
run GATE checked sh -c "cd '$HERE' && '$PY' tests/checked.py"
run GATE printer sh -c "cd '$HERE' && '$PY' tests/printer.py"
run GATE mute sh -c "cd '$HERE' && swipl tests/orphan/mute.pl"
run REPORT reported sh -c "cd '$HERE' && swipl tests/orphan/reported.pl"
"""

TEST_SH = """\
find ./examples -type f -name '*.metta' \\
    ! -path '*/_fixtures/*' -print | LC_ALL=C sort > "$filelist"
SKIPS=$(command grep -v '^#' tests/example_skips.txt | awk 'NF {print $1}')
while IFS= read -r f; do
    rel=${f#./}
    case "
$SKIPS
" in *"
$rel
"*) continue ;;
    esac
    sh run.sh "$f" || exit 1
done < "$filelist"
"""

FILES = {
    "bindings/python/pyproject.toml": '[tool.pytest.ini_options]\npythonpath = ["."]\n',
    ".github/workflows/checks.yml": "run: sh check.sh\n",
    ".github/workflows/ci.yml": "run: sh test.sh\n",
    "bindings/python/tests/test_collected.py": "def test_collected():\n    assert True\n",
    "bindings/python/tests/helpers.py": "def test_uncollected():\n    assert True\n",
    "tests/checked.py": (
        "import sys\n\n\ndef main():\n    return 1\n\n\n"
        'if __name__ == "__main__":\n    sys.exit(main())\n'
    ),
    "tests/printer.py": 'print("a number")\n',
    "tests/prolog/suite.plt": (
        ":- begin_tests(a_unit).\n\ntest(a_plunit_test) :-\n    1 =:= 1.\n\n"
        ":- end_tests(a_unit).\n"
    ),
    "tests/prolog/gate_script.pl": (
        ":- ensure_loaded(loaded_helper).\n:- initialization(main, main).\n\n"
        "main :-\n    checked_thing,\n    loaded_check.\n\n"
        "checked_thing :-\n    \\+ absent_offender(_).\n\nabsent_offender(_) :- fail.\n"
    ),
    "tests/prolog/loaded_helper.pl": "loaded_check :-\n    1 =:= 1.\n",
    "tests/orphan/orphan_check.pl": (
        ":- initialization(main, main).\n\nmain :-\n    1 =:= 1.\n"
    ),
    "tests/orphan/mute.pl": "report :-\n    format('a number~n').\n",
    "tests/orphan/reported.pl": (
        ":- initialization(main, main).\n\nmain :-\n    format('findings~n').\n"
    ),
    "examples/kept.metta": "!(test (+ 1 2) 3)\n",
    "examples/quiet.metta": "!(+ 1 2)\n",
    "examples/skipped.metta": "!(test (+ 1 2) 3)\n",
    "tests/example_skips.txt": (
        "# One path per line, then its reason.\nexamples/skipped.metta   needs a terminal\n"
    ),
}


def build(root: Path, pytest_anchor: str) -> dict[str, int]:
    """Write the tree, and answer with the fixture line each citation sits on."""
    for name, content in FILES.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
    (root / "check.sh").write_text(CHECK_SH.format(pytest_anchor=pytest_anchor))
    (root / "test.sh").write_text(TEST_SH)

    tools = root / "tools"
    tools.mkdir(exist_ok=True)
    for module in ("check_evidence_tags.py", "evidence_runners.py"):
        shutil.copy(HERE / module, tools / module)

    lines = ["% Purpose: fixtures for check_evidence_selftest.py.", "% Guarantees:"]
    at = {}
    for _, names, why in CITATIONS:
        at[names] = len(lines) + 1
        lines.append(f"%   - {why} [{TAG} {WHEN}: {names}].")
    lines += ["% Open Obligations:", "%   To Do: None", "%   Hacks: None",
              "%   Future Enhancements: None", "", "fixture_predicate."]
    (root / "engine").mkdir(exist_ok=True)
    (root / "engine/fixture.pl").write_text("\n".join(lines) + "\n")
    return at


def run(root: Path) -> list[str]:
    finished = subprocess.run(
        [sys.executable, str(root / "tools/check_evidence_tags.py")],
        capture_output=True,
        text=True,
        check=False,
    )
    if finished.returncode not in (0, 1):
        raise SystemExit(f"the checker crashed on the fixture tree:\n{finished.stderr}")
    return finished.stdout.splitlines()



def commit_pin_complaints() -> list[str]:
    """A commit= must name a real commit, and WORKTREE must not survive a release.

    The fixture is a real repository with one commit, so the live object ID is
    known and the fabricated one differs from it only in its tail: that is the
    shape the check found in the tree on 2026-08-26, where a citation carried
    a full object ID sharing eight characters with a real commit and nothing
    else.
    """
    complaints = []
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        build(root, "pytest tests -q -p no:benchmark")
        for command in (
            ["git", "init", "-q"],
            ["git", "add", "-A"],
            ["git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "fixture"],
        ):
            subprocess.run(command, cwd=root, check=True, capture_output=True)
        live = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=root, check=True, capture_output=True, text=True,
        ).stdout.strip()
        fabricated = live[:8] + ("0" * (len(live) - 8) if live[8] != "0" else "1" * (len(live) - 8))

        fixture = root / "engine/fixture.pl"
        lines = fixture.read_text().splitlines()
        head = lines.index("% Open Obligations:")
        planted = [
            f"%   - a live pin [{TAG} {WHEN}: test_collected; commit={live}].",
            f"%   - a dangling pin [{TAG} {WHEN}: test_collected; commit={fabricated}].",
            f"%   - an unresolved pin [{TAG} {WHEN}: test_collected; commit=WORKTREE].",
        ]
        at_live, at_dangling, at_worktree = head + 1, head + 2, head + 3
        fixture.write_text("\n".join(lines[:head] + planted + lines[head:]) + "\n")

        output = run(root)
        for line, what, wanted in (
            (at_live, "a live commit pin", False),
            (at_dangling, "a dangling commit pin", True),
        ):
            reported = [
                item for item in output
                if item.startswith(f"engine/fixture.pl:{line}:") and "commit=" in item
            ]
            if wanted and not reported:
                complaints.append(f"accepted {what}, which names no commit in the repository")
            if not wanted and reported:
                complaints.append(f"rejected {what}: {reported[0]}")
        if not any("commit=WORKTREE placeholder" in item for item in output):
            complaints.append("the report does not count commit=WORKTREE placeholders")

        # The fixture plants rejected citations too, so this tree exits 1
        # either way and the exit code says nothing. The refusal SENTENCE is
        # what discriminates, and it must appear only under RELEASE=1.
        refusal = "still say commit=WORKTREE"
        released = subprocess.run(
            [sys.executable, str(root / "tools/check_evidence_tags.py")],
            cwd=root, capture_output=True, text=True, check=False,
            env={**os.environ, "RELEASE": "1"},
        )
        if refusal not in released.stdout:
            complaints.append(
                f"RELEASE=1 accepted a tree with a commit=WORKTREE placeholder "
                f"at engine/fixture.pl:{at_worktree}"
            )
        if any(refusal in item for item in output):
            complaints.append(
                "an ordinary run refuses commit=WORKTREE, which is the "
                "in-progress spelling and must only fail a release"
            )
    return complaints


def main() -> int:
    complaints = []
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        at = build(root, "pytest tests -q -p no:benchmark")
        output = run(root)
        for accepted, names, why in CITATIONS:
            marker = f"engine/fixture.pl:{at[names]}:"
            reported = [line for line in output if line.startswith(marker)]
            if accepted and reported:
                complaints.append(f"rejected {why}, which is backed: {reported[0]}")
            elif not accepted and not reported:
                complaints.append(f"accepted {why} [{names}], which is not backed")
            elif not accepted and len(reported) > 1:
                complaints.append(f"reported {names} {len(reported)} times, expected once")
        # Nothing else may be said about a tree this file wrote, so a model
        # that has drifted from the runners cannot hide behind the count.
        expected = {f"engine/fixture.pl:{at[names]}:" for accepted, names, _ in CITATIONS}
        for line in output[:-1]:
            if not any(line.startswith(marker) for marker in expected):
                complaints.append(f"reported something the fixture did not plant: {line}")

    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        build(root, "pytest tests -q --moved-since-the-model-was-written")
        output = run(root)
        if not any("no longer contains" in line for line in output):
            complaints.append("a collector whose anchor left the runner went unreported")

    complaints += commit_pin_complaints()

    for complaint in complaints:
        print(complaint)
    print(
        f"{len(complaints)} defect(s) in the evidence gate, over "
        f"{len(CITATIONS)} planted citations, one moved anchor, and three "
        f"commit pins"
    )
    return 1 if complaints else 0


if __name__ == "__main__":
    sys.exit(main())
