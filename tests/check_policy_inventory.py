"""Purpose: derive PeTTa's policy inventory from the running ``&petta``
catalog, join every row to its implementation seam, and reject closed policy
lists that bypass both the catalog and the four explicit exemption reasons.

Assumes:
  - ``swipl`` is on PATH and ``engine/metta.pl`` boots from the repository
    root, the same environment used by the Prolog and vocabulary gate lanes
  - a closed Prolog policy list uses ``memberchk(Value, [a, b])`` and a
    binding policy alias uses ``Name: TypeAlias = Literal[...]``; these are
    the two planted and shipped forms this lane owns
Guarantees:
  - the runtime publishes exactly the seventeen required axes, with one row
    per axis and the knob/default pair recorded in POLICY_SEAMS [tested:
    tests/check_policy_inventory.py; commit=WORKTREE]
  - an unannotated closed list is reported with its path, line and values,
    while an exemption is accepted only when it is immediately adjacent and
    names one of the four allowed categories plus nonempty reason and evidence
    [tested: test_a_planted_closed_policy_list_is_reported_by_the_inventory_lane;
    commit=WORKTREE]
Fails when:
  - the engine cannot boot, emits non-JSON policy rows, publishes a duplicate,
    missing or extra axis, or an implementation seam no longer exists
  - an exemption is malformed, unknown, orphaned, or has no resolvable local
    evidence location
Decides:
  - ``engine/spaces.pl`` is the catalog authority and
    ``bindings/python/petta/vocabularies.py`` is generated from that authority;
    neither can be reported as an independent hardcoded policy list
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

EXEMPTION_REASONS = frozenset(
    {
        "mechanism-internal",
        "arbiter-owned-language-law",
        "codec-version-identity",
        "documented-collision-decision",
    }
)

EXEMPTION_MARKER = "policy-inventory-exempt:"
EXEMPTION_RE = re.compile(
    r"^\s*(?:%|#)\s+policy-inventory-exempt:\s*"
    r"(?P<category>[a-z-]+);\s*"
    r"reason=(?P<reason>[^;]+);\s*"
    r"evidence=(?P<evidence>[^;\s]+)\s*$"
)
PROLOG_CLOSED_LIST = re.compile(
    r"\bmemberchk\s*\(\s*[^,\n]+,\s*\[(?P<values>[^\]\n]+)\]\s*\)"
)
PYTHON_TYPE_ALIAS = re.compile(
    r"\b[A-Za-z_]\w*\s*:\s*TypeAlias\s*=\s*Literal\[(?P<values>[^\]\n]+)\]"
)

SOURCE_ROOTS = (
    Path("engine"),
    Path("lib"),
    Path("bindings/python/petta"),
)
EXCLUDED_PATHS = frozenset(
    {
        Path("engine/spaces.pl"),
        Path("bindings/python/petta/vocabularies.py"),
    }
)


@dataclass(frozen=True)
class PolicySeam:
    """One policy row and the implementation symbol that consumes it."""

    knob: str
    default: str
    path: str
    pattern: str


POLICY_SEAMS: dict[str, PolicySeam] = {
    "dispatch": PolicySeam(
        "dispatch-policy", "MismatchOriginal", "engine/translator.pl", r"^reduce\(\[F\|Args\]"
    ),
    "order": PolicySeam(
        "dispatch-policy", "OrderClause", "engine/translator.pl", r"^reduce\(\[F\|Args\]"
    ),
    "merge": PolicySeam("merge", "depth", "engine/spaces.pl", r"^petta_merged_match\("),
    "agenda": PolicySeam(
        "reduce", "depth-first", "engine/translator.pl", r"^reduce\(\[F\|Args\]"
    ),
    "equality": PolicySeam(
        "==", "structural-identity", "engine/metta.pl", r"^'=='\(A,B,R\)"
    ),
    "errors": PolicySeam("on-error", "abort", "engine/metta.pl", r"^petta_on_error_mode\("),
    "world": PolicySeam(
        "context", "closed-world", "engine/metta.pl", r"^petta_context_world\("
    ),
    "algebra": PolicySeam("annotations", "bool", "engine/metta.pl", r"^petta_k_times\("),
    "storage": PolicySeam(
        "config-memoize", "wtinylfu", "lib/lib_memo.pl", r"^memo_strategy\(wtinylfu\)"
    ),
    "typing": PolicySeam("typing-rule", "strict", "engine/metta.pl", r"^metta_types_match\("),
    "fidelity": PolicySeam(
        "handles", "Exact", "engine/metta.pl", r"^petta_handles_route\("
    ),
    "source-kind": PolicySeam(
        "source", "repeated", "engine/metta.pl", r"^petta_source\("
    ),
    "transaction-mode": PolicySeam(
        "transaction", "all-answers", "engine/metta.pl", r"^petta_transaction\(Goal\)"
    ),
    "atomicity": PolicySeam(
        "writes", "transactional", "engine/spaces.pl", r"petta_in_user_transaction"
    ),
    "save-format": PolicySeam(
        "save", "metta", "bindings/python/petta/_space_persistence.py", r'format == "fast"'
    ),
    "volatility": PolicySeam(
        "volatility", "stable", "engine/metta.pl", r"^metta_function_cacheable\("
    ),
    "determinism": PolicySeam(
        "determinism", "nondet", "engine/metta.pl", r"^apply_declared_determinism\("
    ),
}

QUERY = (
    "consult('engine/metta.pl'), use_module(library(http/json)), "
    "findall(_{axis:A,knob:K,default:D}, "
    "        petta_catalog_row([policy,A,K,D]), Rows), "
    "json_write_dict(current_output, Rows, [width(0)])"
)


def runtime_policy_rows(root: Path) -> list[dict[str, str]]:
    """Ask the running catalog for policy rows; source parsing is not authority."""
    completed = subprocess.run(
        ["swipl", "-q", "-g", QUERY, "-t", "halt"],
        cwd=root,
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "no diagnostic"
        raise RuntimeError(f"swipl policy query exited {completed.returncode}: {detail}")
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"swipl policy query did not emit JSON: {exc}: {completed.stdout!r}") from exc
    if not isinstance(payload, list) or not all(isinstance(row, dict) for row in payload):
        raise RuntimeError(f"swipl policy query emitted a non-row payload: {payload!r}")
    return payload


def validate_policy_rows(root: Path, rows: list[dict[str, str]]) -> list[str]:
    """Join runtime rows to the required axis table and live source seams."""
    findings: list[str] = []
    axes = [str(row.get("axis", "")) for row in rows]
    counts = Counter(axes)
    for axis in POLICY_SEAMS:
        if counts[axis] == 0:
            findings.append(f"&petta: missing policy axis {axis}")
        elif counts[axis] != 1:
            findings.append(f"&petta: policy axis {axis} has {counts[axis]} rows, expected one")
    for axis in sorted(set(axes) - POLICY_SEAMS.keys()):
        findings.append(f"&petta: unexpected policy axis {axis}")

    for row in rows:
        axis = str(row.get("axis", ""))
        seam = POLICY_SEAMS.get(axis)
        if seam is None:
            continue
        knob = str(row.get("knob", ""))
        default = str(row.get("default", ""))
        if (knob, default) != (seam.knob, seam.default):
            findings.append(
                f"&petta: policy {axis} records knob={knob!r} default={default!r}; "
                f"seam requires knob={seam.knob!r} default={seam.default!r}"
            )
        source = root / seam.path
        if not source.is_file():
            findings.append(f"{seam.path}: missing implementation seam for policy {axis}")
            continue
        text = source.read_text(encoding="utf-8")
        if re.search(seam.pattern, text, re.MULTILINE) is None:
            findings.append(
                f"{seam.path}: implementation seam for policy {axis} no longer matches "
                f"{seam.pattern!r}"
            )
    return findings


def _candidate_values(line: str, suffix: str) -> str | None:
    pattern = PROLOG_CLOSED_LIST if suffix == ".pl" else PYTHON_TYPE_ALIAS
    match = pattern.search(line)
    if match is None:
        return None
    return ", ".join(part.strip() for part in match.group("values").split(","))


def _annotation_problem(root: Path, line: str) -> str | None:
    match = EXEMPTION_RE.match(line)
    if match is None:
        return (
            "malformed exemption; expected '<category>; reason=<text>; "
            "evidence=<path:line-or-symbol>'"
        )
    category = match.group("category")
    if category not in EXEMPTION_REASONS:
        return f"unknown exemption reason {category!r}"
    reason = match.group("reason").strip()
    if not reason:
        return "exemption reason text is empty"
    evidence = match.group("evidence").strip()
    if not evidence:
        return "exemption evidence is empty"
    if evidence.startswith(("https://", "http://")):
        return None
    evidence_path, separator, _location = evidence.partition(":")
    if not separator or not (root / evidence_path).is_file():
        return f"exemption evidence location {evidence!r} does not resolve"
    return None


def scan_closed_lists(root: Path) -> list[str]:
    """Report unowned closed lists and invalid adjacent exemptions."""
    findings: list[str] = []
    for source_root in SOURCE_ROOTS:
        directory = root / source_root
        if not directory.exists():
            continue
        for path in sorted(p for p in directory.rglob("*") if p.suffix in {".pl", ".py"}):
            relative = path.relative_to(root)
            if relative in EXCLUDED_PATHS or "__pycache__" in relative.parts:
                continue
            lines = path.read_text(encoding="utf-8").splitlines()
            candidates = {
                number
                for number, line in enumerate(lines, start=1)
                if _candidate_values(line, path.suffix) is not None
            }
            for number, line in enumerate(lines, start=1):
                if EXEMPTION_MARKER not in line:
                    continue
                problem = _annotation_problem(root, line)
                if problem is not None:
                    findings.append(f"{relative}:{number}: {problem}")
                if number + 1 not in candidates:
                    findings.append(
                        f"{relative}:{number}: exemption is not immediately adjacent to a closed list"
                    )
            for number in sorted(candidates):
                values = _candidate_values(lines[number - 1], path.suffix)
                previous = lines[number - 2] if number > 1 else ""
                if EXEMPTION_MARKER not in previous:
                    findings.append(
                        f"{relative}:{number}: closed policy list [{values}] has no adjacent exemption"
                    )
    return findings


def main() -> int:
    """Print the derived table and fail on any catalog, seam or list finding."""
    try:
        rows = runtime_policy_rows(ROOT)
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        print(f"policy inventory: {exc}")
        return 1

    findings = validate_policy_rows(ROOT, rows)
    findings.extend(scan_closed_lists(ROOT))
    by_axis = {str(row["axis"]): row for row in rows if "axis" in row}
    for axis, seam in POLICY_SEAMS.items():
        row = by_axis.get(axis)
        if row is not None:
            print(
                f"policy {axis}: knob={row.get('knob')} default={row.get('default')} "
                f"seam={seam.path}"
            )
    for finding in findings:
        print(finding)
    print(f"policy inventory: {len(rows)} runtime row(s), {len(findings)} finding(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
