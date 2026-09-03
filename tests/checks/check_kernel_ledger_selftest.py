"""Purpose: prove each direction of the KERNEL.md ledger gate turns red.

The plants pass through ``check_kernel_ledger.findings`` itself rather than a
copy of its patterns, so the selftest and production lane cannot drift into
testing different questions.

Assumes: the checked-in KERNEL.md is green against the built engine.
Guarantees:
  - a planted wrong total and a planted omitted special-head row are each
    reported independently, and unwinding each plant restores a clean result
    [tested: this file is its own gate; commit=d7a55be4e931732a02f2178013aed47bb9cde474]
Fails when: the production checker no longer exposes its text-and-inventory
  comparison or the document changes without satisfying that comparison.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import check_kernel_ledger as lane  # noqa: E402


def main() -> int:
    """Plant one count mismatch and one roster omission independently."""
    inventory = lane.engine_inventory()
    text = lane.PAGE.read_text(encoding="utf-8")
    failures: list[str] = []

    if lane.findings(text, inventory):
        failures.append("the unmodified KERNEL.md is not a clean control")

    wrong_total = text.replace(
        f"The translator gives {inventory.total_heads} heads",
        f"The translator gives {inventory.total_heads + 1} heads",
        1,
    )
    if wrong_total == text:
        failures.append("the planted total target vanished from KERNEL.md")
    wrong_total_findings = lane.findings(wrong_total, inventory)
    if not any("total heads" in finding for finding in wrong_total_findings):
        failures.append("a planted wrong total did not turn the production check red")

    planted_head = "get-atoms"
    missing_row = re.sub(
        rf"^\| `{re.escape(planted_head)}` \|.*\n",
        "",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    if missing_row == text:
        failures.append(f"the planted `{planted_head}` row vanished from KERNEL.md")
    missing_findings = lane.findings(missing_row, inventory)
    if not any(f"special head `{planted_head}` has no" in finding for finding in missing_findings):
        failures.append("a planted missing head did not turn the production check red")

    if lane.findings(text, inventory):
        failures.append("the plants did not unwind to the clean control")
    for failure in failures:
        print(failure, file=sys.stderr)
    print(f"kernel-ledger selftest: 2 planted fault(s), {len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
