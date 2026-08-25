"""Purpose: gate semantic refusals on a Python-reference or named MeTTa-law ground.

Assumes:
  - compiler refusals use ``CompileError`` and non-compiler Python semantic
    refusals use ``_grounded_type_error``
Guarantees:
  - every compiler refusal site inherits a structured ground from the central
    ``CompileError`` constructor, every explicit semantic TypeError supplies a
    structured ground, and the segment fence names its MeTTa-law sources
    [tested: tests/check_refusal_grounds_selftest.py; commit=WORKTREE]
Decides:
  - input-shape validation errors are not semantic refusals; this gate owns the
    compiler, Python data-model fences, and MeTTa fragment fences classified by
    GG4-005/GG4-012 at
    ai-python-first-revamp-discussion.md:7493-7502,7568-7573
"""

from __future__ import annotations

import ast
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
PYTHON_PACKAGE = Path("bindings/python/metta")
ERRORS = PYTHON_PACKAGE / "errors.py"
SEGMENTS = Path("engine/spaces/segment_matching.pl")
PYTHON_CITATION = re.compile(r"Python Language Reference section\s+\d")
METTA_LAWS = ("EffectSafety", "SeqFragment", "UnifierMostGeneral", "HostLaws")


@dataclass(frozen=True)
class GateCounts:
    """The refusal populations proved by one gate pass."""

    compile_sites: int
    python_semantic_sites: int
    metta_law_fences: int


def valid_ground(ground: Any) -> bool:
    """Whether structured data names one of the two admitted authorities."""
    kind = getattr(ground, "kind", None)
    citation = getattr(ground, "citation", None)
    if not isinstance(citation, str):
        return False
    if kind == "python-reference":
        return PYTHON_CITATION.search(citation) is not None
    if kind == "metta-law":
        return any(law in citation for law in METTA_LAWS)
    return False


def _call_name(call: ast.Call) -> str | None:
    if isinstance(call.func, ast.Name):
        return call.func.id
    if isinstance(call.func, ast.Attribute):
        return call.func.attr
    return None


def _compile_error_is_central(text: str, filename: str) -> bool:
    tree = ast.parse(text, filename=filename)
    definition = next(
        (
            node
            for node in tree.body
            if isinstance(node, ast.ClassDef) and node.name == "CompileError"
        ),
        None,
    )
    if definition is None:
        return False
    initializer = next(
        (
            node
            for node in definition.body
            if isinstance(node, ast.FunctionDef) and node.name == "__init__"
        ),
        None,
    )
    if initializer is None:
        return False
    for call in (node for node in ast.walk(initializer) if isinstance(node, ast.Call)):
        for keyword in call.keywords:
            if keyword.arg == "ground" and "_compile_ground(construct)" in ast.unparse(
                keyword.value
            ):
                return True
    return False


def scan_refusal_grounds(root: Path) -> tuple[list[str], GateCounts]:
    """Scan every owned refusal site and its central ground mechanism."""
    findings: list[str] = []
    compile_sites = 0
    python_semantic_sites = 0
    package = root / PYTHON_PACKAGE
    if not package.is_dir():
        findings.append(f"{PYTHON_PACKAGE}: Python package is missing")
    else:
        for path in sorted(package.rglob("*.py")):
            relative = path.relative_to(root)
            text = path.read_text(encoding="utf-8")
            try:
                tree = ast.parse(text, filename=str(relative))
            except SyntaxError as exc:
                findings.append(
                    f"{relative}:{exc.lineno or 1}: cannot scan Python: {exc.msg}"
                )
                continue
            for call in (node for node in ast.walk(tree) if isinstance(node, ast.Call)):
                name = _call_name(call)
                if name == "CompileError":
                    compile_sites += 1
                elif name == "_grounded_type_error":
                    python_semantic_sites += 1
                    ground = next(
                        (keyword for keyword in call.keywords if keyword.arg == "ground"),
                        None,
                    )
                    if ground is None:
                        findings.append(
                            f"{relative}:{call.lineno}: semantic TypeError has no ground="
                        )

    errors_path = root / ERRORS
    if not errors_path.is_file():
        findings.append(f"{ERRORS}: central refusal-ground source is missing")
    elif not _compile_error_is_central(
        errors_path.read_text(encoding="utf-8"), str(ERRORS)
    ):
        findings.append(
            f"{ERRORS}: CompileError does not derive ground from _compile_ground(construct)"
        )

    segment_path = root / SEGMENTS
    metta_law_fences = 0
    if not segment_path.is_file():
        findings.append(f"{SEGMENTS}: MeTTa segment refusal source is missing")
    else:
        segment_text = segment_path.read_text(encoding="utf-8")
        if "Kutsia" not in segment_text or "SeqFragment.lean" not in segment_text:
            findings.append(
                f"{SEGMENTS}: segment refusal must cite Kutsia and SeqFragment.lean"
            )
        else:
            metta_law_fences = 1
    return findings, GateCounts(
        compile_sites,
        python_semantic_sites,
        metta_law_fences,
    )


def runtime_ground_findings(root: Path) -> list[str]:
    """Exercise the constructors so data shape, not source spelling, is gated."""
    package_parent = str(root / "bindings/python")
    if package_parent not in sys.path:
        sys.path.insert(0, package_parent)
    from metta.errors import (
        _PYTHON_COMPARISON_GROUND,
        _PYTHON_RICH_COMPARISON_GROUND,
        _compile_ground,
    )

    grounds = (
        _PYTHON_COMPARISON_GROUND,
        _PYTHON_RICH_COMPARISON_GROUND,
        _compile_ground("free identifier"),
        _compile_ground("floor division"),
        _compile_ground(None),
    )
    return [
        f"runtime refusal ground is malformed: {ground!r}"
        for ground in grounds
        if not valid_ground(ground)
    ]


def main() -> int:
    """Print the owned refusal populations and fail on an ungrounded site."""
    findings, counts = scan_refusal_grounds(ROOT)
    findings.extend(runtime_ground_findings(ROOT))
    for finding in findings:
        print(finding)
    print(
        "refusal grounds: "
        f"{counts.compile_sites} CompileError site(s), "
        f"{counts.python_semantic_sites} Python semantic site(s), "
        f"{counts.metta_law_fences} MeTTa-law fence(s), "
        f"{len(findings)} finding(s)"
    )
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
