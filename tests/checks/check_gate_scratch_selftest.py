"""Purpose: prove a later gate run reclaims scratch left by SIGKILL.

Guarantees:
  - a concurrent locked run survives another allocation, a killed holder leaves
    its fixture behind, and the next allocation removes that orphan
    [tested: tests/checks/check_gate_scratch_selftest.py; commit=WORKTREE].
  - check.sh initializes the shared allocator before its first mktemp call and
    closes it from the root EXIT trap [tested: contract_findings; commit=WORKTREE].
Fails when:
  - POSIX SIGKILL or util-linux flock is unavailable; check.sh refuses the same
    environment because safe active-run discrimination would be impossible.
"""

from __future__ import annotations

import os
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "tests" / "checks" / "gate_scratch.sh"

_HOLDER = r"""
. "$2" || exit 2
metta_gate_scratch_open "$1" || exit $?
[ "$TMPDIR" = "$METTA_GATE_SCRATCH" ]
[ "$TMP" = "$METTA_GATE_SCRATCH" ]
[ "$TEMP" = "$METTA_GATE_SCRATCH" ]
: > "$METTA_GATE_SCRATCH/fixture-created"
printf '%s\n' "$METTA_GATE_SCRATCH"
IFS= read -r release
metta_gate_scratch_close
"""

_ONE_RUN = r"""
. "$2" || exit 2
metta_gate_scratch_open "$1" || exit $?
[ "$TMPDIR" = "$METTA_GATE_SCRATCH" ]
probe=$(mktemp)
case "$probe" in "$METTA_GATE_SCRATCH"/*) ;; *) exit 3 ;; esac
rm -f "$probe"
printf '%s\n' "$METTA_GATE_SCRATCH"
metta_gate_scratch_close
"""


def contract_findings(root: Path = ROOT) -> list[str]:
    """Return every missing root-gate integration point."""
    helper = root / "tests" / "checks" / "gate_scratch.sh"
    check = (root / "check.sh").read_text(encoding="utf-8")
    findings: list[str] = []
    if not helper.is_file():
        findings.append("tests/checks/gate_scratch.sh is absent")
    source = '. "$HERE/tests/checks/gate_scratch.sh"'
    opened = 'metta_gate_scratch_open "$HERE"'
    early_close = "trap 'metta_gate_scratch_close' EXIT"
    final_close = "metta_gate_scratch_close || status=1"
    for label, token in (
        ("source", source),
        ("open", opened),
        ("early close", early_close),
        ("final close", final_close),
    ):
        if token not in check:
            findings.append(f"check.sh has no gate-scratch {label} step")
    first_temp = check.find("$(mktemp")
    open_at = check.find(opened)
    close_at = check.find(early_close)
    if first_temp == -1 or open_at == -1 or close_at == -1 or not open_at < close_at < first_temp:
        findings.append(
            "check.sh does not open and guard repository scratch before its first mktemp"
        )
    return findings


def _start_holder(root: Path) -> tuple[subprocess.Popen[str], Path]:
    process = subprocess.Popen(
        ["sh", "-c", _HOLDER, "gate-scratch-holder", str(root), str(HELPER)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert process.stdout is not None
    line = process.stdout.readline().strip()
    if not line:
        assert process.stderr is not None
        error = process.stderr.read()
        status = process.wait()
        message = f"scratch holder exited {status} before allocation: {error}"
        raise AssertionError(message)
    return process, Path(line)


def _one_run(root: Path) -> Path:
    completed = subprocess.run(
        ["sh", "-c", _ONE_RUN, "gate-scratch-run", str(root), str(HELPER)],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        message = f"scratch allocation exited {completed.returncode}: {completed.stderr}"
        raise AssertionError(message)
    return Path(completed.stdout.strip())


def _missing_flock_refuses(root: Path) -> bool:
    """Whether the allocator fails aloud instead of racing without a lock."""
    environment = dict(os.environ)
    environment["PATH"] = "/nonexistent"
    completed = subprocess.run(
        ["/bin/sh", "-c", _ONE_RUN, "gate-scratch-run", str(root), str(HELPER)],
        capture_output=True,
        text=True,
        check=False,
        env=environment,
    )
    return (
        completed.returncode == 2
        and "flock is required to distinguish active runs from orphans" in completed.stderr
    )


def exercise_sigkill_reclamation() -> list[str]:
    """Run the active, killed and subsequent-allocation sequence."""
    failures: list[str] = []
    scratch = ROOT / "ai-tmp"
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="gate-scratch-selftest-", dir=scratch) as name:
        isolated_root = Path(name) / "checkout"
        isolated_root.mkdir()
        if not _missing_flock_refuses(isolated_root):
            failures.append("an allocator without flock did not refuse by name")
        holder, active = _start_holder(isolated_root)
        try:
            concurrent = _one_run(isolated_root)
            if not active.is_dir():
                failures.append("a second allocation reclaimed a still-locked active run")
            if concurrent.exists():
                failures.append("a normal close left its own run directory behind")

            holder.kill()
            status = holder.wait()
            if status != -signal.SIGKILL:
                failures.append(f"the fixture holder exited {status}, not by SIGKILL")
            if not active.is_dir():
                failures.append("SIGKILL did not leave the fixture needed by the control")

            subsequent = _one_run(isolated_root)
            if active.exists():
                failures.append("the next allocation did not reclaim the SIGKILL orphan")
            if subsequent.exists():
                failures.append("the subsequent normal close left its run directory behind")
        finally:
            if holder.poll() is None:
                holder.kill()
                holder.wait()
    return failures


def main() -> int:
    """Run the static integration check and the real-process control."""
    failures = [*contract_findings(), *exercise_sigkill_reclamation()]
    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1
    print("gate scratch: active run kept, SIGKILL orphan reclaimed by next run")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
