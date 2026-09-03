"""Purpose: keep the generated-artifact gate alias in its dependency order.

Guarantees:
  - ``generated-artifacts`` selects exactly ``ledger``, ``aio-mirror`` and
    ``reference``, whose adjacent source order keeps the mirror ahead of the
    page derived from it [tested: tests/checks/check_generated_artifact_group.py;
    commit=WORKTREE].
  - DEVELOPING.md publishes the aggregate command and the reason for the order
    [tested: tests/checks/check_generated_artifact_group.py; commit=WORKTREE].
Fails when:
  - check.sh stops keeping its selectable lane declarations as literal
    ``run GATE`` calls; the evidence runner inventory relies on the same form.
"""

from __future__ import annotations

import re
import shlex
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXPECTED = ("ledger", "aio-mirror", "reference")


def findings(root: Path = ROOT) -> list[str]:
    """Return every divergence between the alias, execution order and guide."""
    check = (root / "check.sh").read_text(encoding="utf-8")
    guide = (root / "DEVELOPING.md").read_text(encoding="utf-8")
    defects: list[str] = []

    assignment = re.search(
        r'^GENERATED_ARTIFACT_LANES=(?P<value>"[^"]*"|\'[^\']*\')$',
        check,
        re.MULTILINE,
    )
    words = shlex.split(assignment.group("value")) if assignment else []
    configured = tuple(words[0].split()) if len(words) == 1 else ()
    if configured != EXPECTED:
        defects.append(
            "generated-artifacts must select exactly "
            f"{' '.join(EXPECTED)}; got {' '.join(configured) or '<missing>'}"
        )

    expansion = re.compile(
        r'^\s*\*" generated-artifacts "\*\) '
        r'WANT="\$WANT \$GENERATED_ARTIFACT_LANES" ;;$',
        re.MULTILINE,
    )
    if not expansion.search(check):
        defects.append("generated-artifacts does not expand the configured lane group")

    lane_order = tuple(
        match.group("name")
        for match in re.finditer(
            r"^run GATE\s+(?P<name>[a-z0-9-]+)\s", check, re.MULTILINE
        )
    )
    try:
        start = lane_order.index(EXPECTED[0])
    except ValueError:
        actual = ()
    else:
        actual = lane_order[start : start + len(EXPECTED)]
    if actual != EXPECTED:
        defects.append(
            "generated-artifact lanes must be adjacent in remedy order; "
            f"got {' '.join(actual) or '<missing>'}"
        )

    command = 'CHECK_PY="$PY" sh check.sh generated-artifacts'
    if command not in guide:
        defects.append(f"DEVELOPING.md does not publish `{command}`")
    if "`aio-mirror` must precede `reference`" not in guide:
        defects.append("DEVELOPING.md does not explain the mirror-before-pages order")

    return defects


def main() -> int:
    """Print the contract verdict for the blocking gate."""
    defects = findings()
    if defects:
        for defect in defects:
            print(defect, file=sys.stderr)
        return 1
    print("generated-artifacts: alias, three-lane order and guide agree")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
