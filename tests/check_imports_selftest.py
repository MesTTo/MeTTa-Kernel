"""Purpose: prove the blocking import-layering lane rejects a forbidden edge.

Assumes:
  - pyproject.toml and bindings/python/metta describe the tree checked by
    check.sh, and import-linter is installed in the selected interpreter
Guarantees:
  - the unmodified scratch tree keeps all three contracts, while a planted
    module-level metta._tokens -> metta._trace import exits nonzero and is
    named in the broken core contract [tested:
    test_a_planted_module_level_import_is_rejected; commit=WORKTREE]
Fails when:
  - the gate command, contract names, or planted modules drift without this
    discrimination proof being updated
Owns resources:
  - a TemporaryDirectory containing the copied config and package; it is
    removed on success, assertion failure, or interruption
Decides:
  - metta._tokens -> metta._trace is the minimal planted core-to-satellite
    edge used to exercise the production contract; each linter run has the
    gate's 290-second foreground ceiling
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PYTHON_ROOT = ROOT / "bindings" / "python"
COMMAND_TIMEOUT_SECONDS = 290
IMPORTS_COMMAND = (
    "from importlinter.cli import lint_imports_command; "
    "lint_imports_command()"
)


def _run_imports(root: Path) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["PYTHONPATH"] = str(root)
    return subprocess.run(
        [sys.executable, "-c", IMPORTS_COMMAND],
        cwd=root,
        env=env,
        check=False,
        capture_output=True,
        text=True,
        timeout=COMMAND_TIMEOUT_SECONDS,
    )


def test_a_planted_module_level_import_is_rejected() -> None:
    """Require one forbidden edge to turn the same clean command red by name."""
    check_script = (ROOT / "check.sh").read_text(encoding="utf-8")
    assert IMPORTS_COMMAND in check_script

    with tempfile.TemporaryDirectory(prefix="petta-imports-selftest-") as directory:
        scratch = Path(directory)
        shutil.copy2(ROOT / "pyproject.toml", scratch / "pyproject.toml")
        shutil.copytree(
            PYTHON_ROOT / "metta",
            scratch / "metta",
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
        )

        clean = _run_imports(scratch)
        clean_output = clean.stdout + clean.stderr
        assert clean.returncode == 0, clean_output
        assert "Contracts: 3 kept, 0 broken." in clean_output, clean_output
        print(
            "imports selftest: clean scratch exited 0 with "
            "Contracts: 3 kept, 0 broken."
        )

        plant = scratch / "metta" / "_tokens.py"
        with plant.open("a", encoding="utf-8") as stream:
            stream.write("\nimport metta._trace  # imports-selftest planted violation\n")

        broken = _run_imports(scratch)
        broken_output = broken.stdout + broken.stderr
        assert broken.returncode != 0, broken_output
        for expected in (
            "core does not import satellites BROKEN",
            "Contracts: 2 kept, 1 broken.",
            "metta._tokens is not allowed to import metta._trace:",
            "metta._tokens -> metta._trace",
        ):
            assert expected in broken_output, broken_output
        print(
            "imports selftest: planted metta._tokens -> metta._trace exited "
            f"{broken.returncode} and was reported"
        )


def main() -> int:
    """Run the planted case without depending on pytest collection."""
    failures: list[str] = []
    try:
        test_a_planted_module_level_import_is_rejected()
    except AssertionError as exc:
        failures.append(f"test_a_planted_module_level_import_is_rejected: {exc}")
    for failure in failures:
        print(failure)
    print(f"imports selftest: 1 planted case(s), {len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
