"""Purpose: prove the refusal-ground gate turns planted omissions red.

Guarantees:
  - a missing TypeError ground, a non-central CompileError constructor, and a
    segment fence without its named MeTTa law fail independently, while the
    complete fixture passes [tested: tests/checks/check_refusal_grounds_selftest.py;
    commit=acb40f1912f131ae088083d1af29b4b283019bea]
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

from check_refusal_grounds import scan_refusal_grounds


def _write(root: Path, relative: str, text: str) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _fixture(*, grounded_call: bool = True, central: bool = True, law: bool = True):
    directory = tempfile.TemporaryDirectory()
    root = Path(directory.name)
    ground_argument = ", ground=PYTHON_GROUND" if grounded_call else ""
    central_value = (
        "ground=ground or _compile_ground(construct)" if central else "ground=ground"
    )
    _write(
        root,
        "bindings/python/metta/errors.py",
        "def _compile_ground(construct):\n"
        "    return construct\n"
        "class CompileError(Exception):\n"
        "    def __init__(self, message, *, construct=None, ground=None):\n"
        f"        super().__init__(message, {central_value})\n",
    )
    _write(
        root,
        "bindings/python/metta/refusal.py",
        "def refuse():\n"
        f"    raise _grounded_type_error('fixture'{ground_argument})\n",
    )
    segment_ground = "Kutsia; SeqFragment.lean" if law else "a finite fragment"
    _write(root, "engine/spaces/segment_matching.pl", segment_ground + "\n")
    return directory, root


def test_a_complete_refusal_fixture_passes() -> None:
    """Accept a fixture whose refusal sites all carry valid grounds."""
    directory, root = _fixture()
    try:
        findings, counts = scan_refusal_grounds(root)
    finally:
        directory.cleanup()
    assert findings == []
    assert counts.compile_sites == 0
    assert counts.python_semantic_sites == 1
    assert counts.metta_law_fences == 1


def test_a_planted_semantic_type_error_without_ground_is_reported() -> None:
    """Reject a semantic TypeError helper call that omits ground data."""
    directory, root = _fixture(grounded_call=False)
    try:
        findings, _counts = scan_refusal_grounds(root)
    finally:
        directory.cleanup()
    assert findings == [
        "bindings/python/metta/refusal.py:2: semantic TypeError has no ground="
    ]


def test_a_planted_noncentral_compile_error_ground_is_reported() -> None:
    """Reject a CompileError constructor that bypasses central grounding."""
    directory, root = _fixture(central=False)
    try:
        findings, _counts = scan_refusal_grounds(root)
    finally:
        directory.cleanup()
    assert findings == [
        "bindings/python/metta/errors.py: CompileError does not derive ground "
        "from _compile_ground(construct)"
    ]


def test_a_planted_segment_fence_without_a_named_law_is_reported() -> None:
    """Reject the segment fence when its named MeTTa law is absent."""
    directory, root = _fixture(law=False)
    try:
        findings, _counts = scan_refusal_grounds(root)
    finally:
        directory.cleanup()
    assert findings == [
        "engine/spaces/segment_matching.pl: segment refusal must cite Kutsia "
        "and SeqFragment.lean"
    ]


def main() -> int:
    """Run the planted cases without depending on pytest collection."""
    tests = (
        test_a_complete_refusal_fixture_passes,
        test_a_planted_semantic_type_error_without_ground_is_reported,
        test_a_planted_noncentral_compile_error_ground_is_reported,
        test_a_planted_segment_fence_without_a_named_law_is_reported,
    )
    failures: list[str] = []
    for test in tests:
        try:
            test()
        except AssertionError as exc:
            failures.append(f"{test.__name__}: {exc}")
    for failure in failures:
        print(failure)
    print(
        f"refusal-ground selftest: {len(tests)} planted case(s), "
        f"{len(failures)} failure(s)"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
