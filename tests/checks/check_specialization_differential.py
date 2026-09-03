"""Purpose: run the specialization differential over the shipped example corpus.

Assumes:
  - ``engine/main.pl`` is the standalone engine entry point and the caller has
    rebuilt the QLF set before asking this gate for evidence
  - ``example_parity.corpus`` is the single definition of runnable examples
Guarantees:
  - every corpus file runs in its own process with specialization verification
    enabled, and a disagreement or failed verifier process makes the gate fail
    while naming the file
  - ``specialization_finding`` is the same per-file detector imported by the
    planted selftest, so the selftest cannot drift from the production scan
    [tested: tests/checks/check_specialization_differential_selftest.py;
    commit=WORKTREE]
Fails when:
  - SWI-Prolog or the engine cannot start; infrastructure failure is loud
    rather than being mistaken for a corpus with no disagreements.
"""

from __future__ import annotations

import os
import subprocess
import sys
from collections.abc import Iterable
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "extensions" / "python" / "tools"
sys.path.insert(0, str(TOOLS))

from example_parity import corpus  # noqa: E402

MARKER = "metta_specialization_disagrees"


def _display(path: Path, root: Path) -> str:
    """A stable repository-relative label, or the absolute external path."""
    resolved = path.resolve()
    try:
        return str(resolved.relative_to(root.resolve()))
    except ValueError:
        return str(resolved)


def _diagnostic_lines(text: str, marker: str | None = None) -> str:
    """At most three lines around the decisive output, matching the old lane."""
    lines = text.strip().splitlines()
    if not lines:
        return "no output"
    if marker is None:
        return "\n".join(lines[-3:])
    index = next(i for i, line in enumerate(lines) if marker in line)
    return "\n".join(lines[index:index + 3])


def specialization_finding(
    path: Path,
    *,
    root: Path = ROOT,
    entrypoint: Path | None = None,
) -> str | None:
    """Return the named reason one source did not prove specialization parity."""
    label = _display(path, root)
    argument = label if path.resolve().is_relative_to(root.resolve()) else str(path)
    entrypoint = root / "engine" / "main.pl" if entrypoint is None else entrypoint
    entrypoint_argument = _display(entrypoint, root)
    environment = os.environ.copy()
    environment["METTA_VERIFY_SPECIALIZATIONS"] = "1"
    done = subprocess.run(
        [
            "swipl",
            "--stack_limit=8g",
            "-q",
            "-s",
            entrypoint_argument,
            "--",
            argument,
            "extensions",
            "silent",
        ],
        cwd=root,
        env=environment,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        check=False,
    )

    output = done.stdout + done.stderr
    if MARKER in output:
        return f"{label}: {_diagnostic_lines(output, MARKER)}"
    if any(line.lstrip().startswith("ERROR:") for line in output.splitlines()):
        return f"{label}: verifier reported an error\n{_diagnostic_lines(output)}"
    if done.returncode != 0:
        return (
            f"{label}: specialization verifier exited {done.returncode}\n"
            f"{_diagnostic_lines(output)}"
        )
    return None


def specialization_findings(
    paths: Iterable[Path], *, root: Path = ROOT
) -> list[str]:
    """Run independent source files concurrently and preserve corpus order."""
    ordered = list(paths)
    with ThreadPoolExecutor() as pool:
        checked = pool.map(
            lambda path: specialization_finding(path, root=root), ordered
        )
        return [finding for finding in checked if finding is not None]


def main() -> int:
    """Print every corpus failure and return whether the differential held."""
    findings = specialization_findings(corpus(ROOT))
    for finding in findings:
        print(finding)
    if findings:
        return 1
    print("specialization differential: 0 disagreements")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
