"""Purpose: prove tests/conformance/leatta.py's --gate-areas-file discriminates
by area, using a fixture corpus rather than LeaTTa's own, because the half
that matters most, "a currently clean gated area regresses to red", needs a
currently clean area, and measured 2026-08-18 none of LeaTTa's real nine
areas is: control-stdlib 2/13, eval-core 7/27, grounded 1/36, matching 7/11,
metaprogramming 1/9, modules 0/28, spaces 0/17, types-basic 28/75,
types-meta 4/20 checkable files agree. Running the real checker against a
small corpus this file writes and controls proves the isolation the real
corpus cannot demonstrate today, the same way check_evidence_selftest.py
proves check_evidence_tags.py against planted fixtures rather than trusting
that this repository being clean means the checker can see a violation.

Two areas, alpha and beta, each one trivial deterministic MEASURED block run
through the real engine via the real compare()/summarize() path. alpha is
named in the gate-areas file; beta is not. Runs: both clean (exit 0), only
alpha's expectation broken (exit 1, blamed on alpha by name, beta still
prints as agreeing), alpha restored and only beta's broken instead (exit 0
despite the printed difference, because beta was never promoted), both
restored (reproduces the first run byte for byte). Then the two hard-error
paths: a gate-areas file naming an area the corpus does not have, and
--area combined with --gate-areas-file.
Guarantees:
  - a promoted area's regression fails the run and names that area; an
    unpromoted area's identical kind of regression prints but never fails
    the run [tested 2026-08-18: tests/conformance/leatta_gate_selftest.py].
Fails when:
  - the real engine does not boot; every lane in check.sh shares that
    assumption and this file adds nothing beyond it.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENGINE = HERE.parents[1]

ALPHA_CLEAN = """\
; PURPOSE: fixture, alpha area, promoted to GATE by this self-test.
; MEASURED: printed on stdout:
;   [2]
; STATUS: conforms.

!(+ 1 1)
"""
ALPHA_BROKEN = ALPHA_CLEAN.replace("[2]", "[3]")

BETA_CLEAN = """\
; PURPOSE: fixture, beta area, deliberately left unpromoted.
; MEASURED: printed on stdout:
;   [4]
; STATUS: conforms.

!(+ 2 2)
"""
BETA_BROKEN = BETA_CLEAN.replace("[4]", "[5]")

GATE_FILE = "alpha\n# beta is deliberately NOT listed\n"


def build(root: Path) -> Path:
    """Write the fixture corpus and its gate-areas file, and answer the
    latter's path."""
    (root / "alpha").mkdir(parents=True)
    (root / "beta").mkdir(parents=True)
    (root / "alpha/probe.metta").write_text(ALPHA_CLEAN)
    (root / "beta/probe.metta").write_text(BETA_CLEAN)
    gate_file = root / "gate_areas.txt"
    gate_file.write_text(GATE_FILE)
    return gate_file


def run(corpus: Path, gate_file: Path | None, area: str = "") -> subprocess.CompletedProcess[str]:
    args = [
        sys.executable, str(HERE / "leatta.py"),
        "--corpus", str(corpus), "--engine", str(ENGINE),
        "--timeout", "25", "--show", "20",
    ]
    if gate_file is not None:
        args += ["--gate-areas-file", str(gate_file)]
    if area:
        args += ["--area", area]
    return subprocess.run(args, capture_output=True, text=True, check=False)


def main() -> int:
    complaints: list[str] = []
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        gate_file = build(root)

        clean = run(root, gate_file)
        if clean.returncode != 0:
            complaints.append(
                f"both areas clean but exit was {clean.returncode}:\n{clean.stdout}"
            )
        if "[alpha, GATE]" not in clean.stdout or "[beta, REPORT]" not in clean.stdout:
            complaints.append(f"area tiers not labelled as expected:\n{clean.stdout}")

        (root / "alpha/probe.metta").write_text(ALPHA_BROKEN)
        alpha_broken = run(root, gate_file)
        if alpha_broken.returncode == 0:
            complaints.append(
                f"alpha (GATE) regressed but the run stayed green:\n{alpha_broken.stdout}"
            )
        if "regressed: ['alpha']" not in alpha_broken.stdout:
            complaints.append(
                f"the regression was not blamed on alpha alone:\n{alpha_broken.stdout}"
            )
        if "beta, REPORT]: 1/1" not in alpha_broken.stdout:
            complaints.append(f"beta stopped agreeing while untouched:\n{alpha_broken.stdout}")

        (root / "alpha/probe.metta").write_text(ALPHA_CLEAN)
        (root / "beta/probe.metta").write_text(BETA_BROKEN)
        beta_broken = run(root, gate_file)
        if beta_broken.returncode != 0:
            complaints.append(
                f"beta (REPORT) regressed and the run went red anyway:\n{beta_broken.stdout}"
            )
        if "expected 5  observed 4" not in beta_broken.stdout:
            complaints.append(f"beta's difference was not printed:\n{beta_broken.stdout}")
        if "every promoted area conforms" not in beta_broken.stdout:
            complaints.append(
                f"an unpromoted regression was counted against a promotion:\n{beta_broken.stdout}"
            )

        (root / "beta/probe.metta").write_text(BETA_CLEAN)
        restored = run(root, gate_file)
        if restored.returncode != 0 or restored.stdout != clean.stdout:
            complaints.append(
                "restoring both files did not reproduce the clean baseline byte for byte"
            )

        missing = run(root, root / "does_not_exist.txt")
        if missing.returncode == 0:
            complaints.append("a gate-areas file that does not exist was accepted")

        unknown_file = root / "unknown_area.txt"
        unknown_file.write_text("alpha\nnot-a-real-area\n")
        unknown = run(root, unknown_file)
        if unknown.returncode == 0 or "unknown area" not in unknown.stderr:
            complaints.append(
                f"an unrecognised area name in the gate file was accepted:\n{unknown.stderr}"
            )

        combined = run(root, gate_file, area="alpha")
        if combined.returncode == 0 or "not both" not in combined.stderr:
            complaints.append(
                f"--area with --gate-areas-file was silently accepted:\n{combined.stderr}"
            )

        # The authority model: the arbiter's word settles. A STATUS of
        # diverges is a commitment, the arbiter ruling against upstream, so
        # a difference there is engine backlog; only an undecided-* status
        # awaits the arbiter's own ruling.
        (root / "gamma").mkdir()
        (root / "gamma/committed.metta").write_text(
            BETA_CLEAN.replace("[4]", "[9]").replace("conforms", "diverges"))
        (root / "gamma/open.metta").write_text(
            BETA_CLEAN.replace("!(+ 2 2)", "!(+ 3 3)").replace("[4]", "[9]")
            .replace("conforms", "undecided-upstream"))
        authority = run(root, None)
        if "await the arbiter's own ruling" not in authority.stdout:
            complaints.append(
                f"authority split not reported:\n{authority.stdout}")
        if "diverges: 1" not in authority.stdout or "undecided-upstream: 1" not in authority.stdout:
            complaints.append(
                f"status breakdown missing:\n{authority.stdout}")

        # The promotion consequence of that model: a PROMOTED area whose only
        # differences are the arbiter's own commitments and open questions is
        # CLEAN, or no area could ever promote without adopting every
        # deliberate divergence. A file claiming agreement while differing is
        # what blocks, and only that.
        gamma_gate = root / "gamma-gate.txt"
        gamma_gate.write_text("alpha\ngamma\n")
        committed_clean = run(root, gamma_gate)
        if committed_clean.returncode != 0:
            complaints.append(
                "a promoted area regressed on its own committed divergences:\n"
                f"{committed_clean.stdout}")
        if "0 of the 2 differing claim agreement" not in committed_clean.stdout:
            complaints.append(
                f"blocking split not reported:\n{committed_clean.stdout}")
        (root / "gamma/stale.metta").write_text(
            BETA_CLEAN.replace("!(+ 2 2)", "!(+ 4 4)").replace("[4]", "[9]"))
        stale = run(root, gamma_gate)
        if stale.returncode == 0 or "gamma" not in stale.stdout:
            complaints.append(
                "a conforms-claiming file that differs did not block its "
                f"promoted area by name:\n{stale.stdout}")
        (root / "gamma/stale.metta").unlink()

    for complaint in complaints:
        print(complaint)
    print(f"{len(complaints)} defect(s) in the per-area leatta gate, over 13 checks")
    return 1 if complaints else 0


if __name__ == "__main__":
    sys.exit(main())
