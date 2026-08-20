"""Purpose: prove the policy-inventory lane discriminates an undeclared
closed list from each valid exemption and from the two authority-owned files.

Guarantees:
  - a planted unannotated list is reported with its file, line and values
    [tested: test_a_planted_closed_policy_list_is_reported_by_the_inventory_lane;
    commit=WORKTREE]
  - all four exemption categories pass only with adjacent nonempty reason and
    evidence fields; missing and unknown reasons fail independently
    [tested: tests/check_policy_inventory_selftest.py; commit=WORKTREE]
  - the catalog authority and generated vocabulary output are excluded
    without an annotation [tested: tests/check_policy_inventory_selftest.py;
    commit=WORKTREE]
Fails when:
  - run against a tree it did not create; every assertion is against a fresh
    temporary fixture with exact findings
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

from check_policy_inventory import EXEMPTION_REASONS, scan_closed_lists


def _write(root: Path, relative: str, text: str) -> Path:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def test_a_planted_closed_policy_list_is_reported_by_the_inventory_lane() -> None:
    """The row's named acceptance proof: one list turns the lane red by name."""
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        _write(root, "engine/planted.pl", "% fixture\nallowed(X) :- memberchk(X, [red, blue]).\n")
        findings = scan_closed_lists(root)
    assert findings == [
        "engine/planted.pl:2: closed policy list [red, blue] has no adjacent exemption"
    ]


def test_each_recorded_exemption_reason_is_accepted() -> None:
    """Each allowed category uses the same strict adjacent grammar."""
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        path = "engine/exemptions.pl"
        lines: list[str] = []
        for index, category in enumerate(sorted(EXEMPTION_REASONS), start=1):
            lines.append(
                f"% policy-inventory-exempt: {category}; "
                f"reason=fixture reason {index}; evidence={path}:{index}"
            )
            lines.append(f"allowed_{index}(X) :- memberchk(X, [value_{index}, other_{index}]).")
        _write(root, path, "\n".join(lines) + "\n")
        findings = scan_closed_lists(root)
    assert findings == []


def test_an_exemption_without_a_reason_is_reported() -> None:
    """An empty reason cannot turn a closed list green."""
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        _write(
            root,
            "lib/missing_reason.pl",
            "% policy-inventory-exempt: mechanism-internal; reason=; "
            "evidence=lib/missing_reason.pl:2\n"
            "allowed(X) :- memberchk(X, [one, two]).\n",
        )
        findings = scan_closed_lists(root)
    assert any("lib/missing_reason.pl:1: malformed exemption" in item for item in findings)


def test_an_unknown_exemption_reason_is_reported() -> None:
    """A plausible fifth category cannot silently extend the grammar."""
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        _write(
            root,
            "engine/unknown.pl",
            "% policy-inventory-exempt: convenient-local-default; reason=fixture; "
            "evidence=engine/unknown.pl:2\n"
            "allowed(X) :- memberchk(X, [one, two]).\n",
        )
        findings = scan_closed_lists(root)
    assert findings == [
        "engine/unknown.pl:1: unknown exemption reason 'convenient-local-default'"
    ]


def test_catalog_authority_and_generated_output_are_not_findings() -> None:
    """The two files derived by construction do not need circular exemptions."""
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        _write(root, "engine/spaces.pl", "allowed(X) :- memberchk(X, [one, two]).\n")
        _write(
            root,
            "bindings/python/petta/vocabularies.py",
            'SaveFormat: TypeAlias = Literal["metta", "fast"]\n',
        )
        findings = scan_closed_lists(root)
    assert findings == []


def main() -> int:
    """Run every planted case without depending on pytest collection."""
    tests = (
        test_a_planted_closed_policy_list_is_reported_by_the_inventory_lane,
        test_each_recorded_exemption_reason_is_accepted,
        test_an_exemption_without_a_reason_is_reported,
        test_an_unknown_exemption_reason_is_reported,
        test_catalog_authority_and_generated_output_are_not_findings,
    )
    failures: list[str] = []
    for test in tests:
        try:
            test()
        except AssertionError as exc:
            failures.append(f"{test.__name__}: {exc}")
    for failure in failures:
        print(failure)
    print(f"policy inventory selftest: {len(tests)} planted case(s), {len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
