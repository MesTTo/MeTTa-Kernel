"""Purpose: derive PeTTa's policy inventory from the running ``&petta``
catalog, join every row to its implementation seam, and reject closed policy
lists that bypass both the catalog and the four explicit exemption reasons.

Assumes:
  - ``swipl`` is on PATH and ``engine/metta.pl`` boots from the repository
    root, the same environment used by the Prolog and vocabulary gate lanes
Guarantees:
  - the runtime publishes exactly the twenty required axes, with one row
    per axis and the knob/default pair recorded in POLICY_SEAMS; the algebra
    row also derives and validates each shipped semiring law claim [tested:
    tests/check_policy_inventory.py; commit=9e7d5dc2cad810940e5386d52636ac6946df279d]
  - unannotated Python Literal expressions and list/set membership, plus
    single- or multiline Prolog member/2 and memberchk/2 lists, are reported
    with path, line and values; an exemption is accepted only when immediately
    adjacent and names one of four categories plus a nonempty reason and an
    existing local source line or symbol
    [tested: test_a_planted_closed_policy_list_is_reported_by_the_inventory_lane;
    commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3]
Fails when:
  - the engine cannot boot, emits non-JSON policy rows, publishes a duplicate,
    missing or extra axis, or an implementation seam no longer exists
  - an exemption is malformed, unknown, orphaned, or has no resolvable local
    evidence location
Decides:
  - only ``petta_catalog_preset/1`` terms in ``engine/spaces.pl`` are catalog
    authority; unrelated closed lists in that file remain findings, while
    ``bindings/python/metta/vocabularies.py`` is generated and excluded
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import ast
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
    r"\b(?:memberchk|member)\s*\(\s*[^,]+?,\s*"
    r"\[(?P<values>[^\]]+)\]\s*\)",
    re.DOTALL,
)
CATALOG_PRESET = re.compile(
    r"^\s*petta_catalog_preset\s*\(\s*\[.*?\]\s*\)\s*\.",
    re.DOTALL | re.MULTILINE,
)

SOURCE_ROOTS = (
    Path("engine"),
    Path("lib"),
    Path("bindings/python/metta"),
)
EXCLUDED_PATHS = frozenset(
    {
        Path("bindings/python/metta/vocabularies.py"),
    }
)

REQUIRED_ALGEBRA_LAWS = {
    "ranked": frozenset({"ordered"}),
    "prob": frozenset({"ordered"}),
}
ALGEBRA_LAW_SEAM = (
    "engine/metta.pl",
    r"^\s*petta_vocabulary_claim\(semiring,\s*Semiring,\s*ordered\)\.",
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
    "agenda": PolicySeam("reduce", "depth-first", "engine/translator.pl", r"^reduce\(\[F\|Args\]"),
    "equality": PolicySeam("==", "structural-identity", "engine/metta.pl", r"^'=='\(A,B,R\)"),
    "errors": PolicySeam("on-error", "abort", "engine/metta.pl", r"^petta_on_error_mode\("),
    "world": PolicySeam("context", "closed-world", "engine/metta.pl", r"^petta_context_world\("),
    "algebra": PolicySeam("annotations", "bool", "engine/metta.pl", r"^petta_k_extend\("),
    "storage": PolicySeam(
        "config-memoize", "wtinylfu", "lib/lib_memo.pl", r"^memo_strategy\(wtinylfu\)"
    ),
    "caching": PolicySeam(
        "cache",
        "automatic",
        "lib/lib_memo.pl",
        r"^memo_automatic_function_decision\(",
    ),
    "typing": PolicySeam("typing-rule", "strict", "engine/metta.pl", r"^metta_types_match\("),
    "fidelity": PolicySeam("handles", "Exact", "engine/metta.pl", r"^petta_handles_route\("),
    "source-kind": PolicySeam("source", "repeated", "engine/metta.pl", r"^petta_source\("),
    "transaction-mode": PolicySeam(
        "transaction", "all-answers", "engine/metta.pl", r"^petta_transaction\(Goal\)"
    ),
    "atomicity": PolicySeam(
        "writes", "transactional", "engine/spaces.pl", r"petta_in_user_transaction"
    ),
    "delivery": PolicySeam(
        "events", "per-write-exactly", "engine/metta.pl", r"^petta_event_capability\("
    ),
    "reaction-order": PolicySeam(
        "agenda", "declaration", "engine/metta.pl", r"^petta_agenda_order\("
    ),
    "save-format": PolicySeam(
        "save", "metta", "bindings/python/metta/_space_persistence.py", r'format == "fast"'
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
    "        petta_catalog_row([policy,A,K,D]), Policies), "
    "findall(_{semiring:S,laws:L}, "
    "        petta_catalog_row([claim,semiring,S|L]), Laws), "
    "petta_catalog_row([vocabulary,semiring|Semirings]), "
    "json_write_dict(current_output, "
    "                _{policies:Policies,algebra_laws:Laws,semirings:Semirings}, "
    "                [width(0)])"
)


def runtime_inventory(
    root: Path,
) -> tuple[list[dict[str, str]], list[dict[str, object]], list[str]]:
    """Ask the running catalog for policies, semirings and algebra laws."""
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
        raise RuntimeError(
            f"swipl policy query did not emit JSON: {exc}: {completed.stdout!r}"
        ) from exc
    if not isinstance(payload, dict):
        raise RuntimeError(f"swipl policy query emitted a non-inventory payload: {payload!r}")
    policies = payload.get("policies")
    laws = payload.get("algebra_laws")
    semirings = payload.get("semirings")
    if not isinstance(policies, list) or not all(isinstance(row, dict) for row in policies):
        raise RuntimeError(f"swipl policy query emitted invalid policy rows: {policies!r}")
    if not isinstance(laws, list) or not all(isinstance(row, dict) for row in laws):
        raise RuntimeError(f"swipl policy query emitted invalid algebra law rows: {laws!r}")
    if not isinstance(semirings, list) or not all(isinstance(item, str) for item in semirings):
        raise RuntimeError(f"swipl policy query emitted invalid semiring values: {semirings!r}")
    return policies, laws, semirings


def runtime_policy_rows(root: Path) -> list[dict[str, str]]:
    """Compatibility entry point returning the runtime policy rows."""
    policies, _laws, _semirings = runtime_inventory(root)
    return policies


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


def validate_algebra_laws(
    root: Path, rows: list[dict[str, object]], semirings: list[str]
) -> list[str]:
    """Validate the semiring law rows derived from the runtime catalog."""
    findings: list[str] = []
    observed: dict[str, list[str]] = {}
    for row in rows:
        semiring = row.get("semiring")
        laws = row.get("laws")
        if (
            not isinstance(semiring, str)
            or not isinstance(laws, list)
            or not all(isinstance(law, str) for law in laws)
        ):
            findings.append(f"&petta: malformed algebra law row {row!r}")
            continue
        if semiring not in semirings:
            findings.append(f"&petta: algebra law row names undeclared semiring {semiring!r}")
        observed.setdefault(semiring, []).extend(laws)

    for semiring, required in REQUIRED_ALGEBRA_LAWS.items():
        laws = observed.get(semiring, [])
        counts = Counter(laws)
        for law in required:
            if counts[law] == 0:
                findings.append(f"&petta: semiring {semiring} is missing law {law}")
            elif counts[law] != 1:
                findings.append(
                    f"&petta: semiring {semiring} has {counts[law]} claims for law {law}"
                )
        for law in sorted(set(laws) - required):
            findings.append(f"&petta: semiring {semiring} has unexpected law {law}")
    for semiring in sorted(set(observed) - REQUIRED_ALGEBRA_LAWS.keys()):
        findings.append(f"&petta: unexpected algebra law claims for semiring {semiring}")

    path, pattern = ALGEBRA_LAW_SEAM
    source = root / path
    if not source.is_file():
        findings.append(f"{path}: missing implementation seam for algebra law claims")
    elif re.search(pattern, source.read_text(encoding="utf-8"), re.MULTILINE) is None:
        findings.append(
            f"{path}: implementation seam for algebra law claims no longer matches {pattern!r}"
        )
    return findings


@dataclass(frozen=True)
class ClosedListCandidate:
    """One syntactically closed policy list and its first source line."""

    line: int
    values: str


def _normalise_values(values: str) -> str:
    return ", ".join(part.strip() for part in values.split(","))


def _prolog_candidates(relative: Path, text: str) -> list[ClosedListCandidate]:
    authority_spans = (
        [(match.start(), match.end()) for match in CATALOG_PRESET.finditer(text)]
        if relative == Path("engine/spaces.pl")
        else []
    )
    candidates: list[ClosedListCandidate] = []
    for match in PROLOG_CLOSED_LIST.finditer(text):
        values = match.group("values")
        if "|" in values:
            continue
        if any(start <= match.start() < end for start, end in authority_spans):
            continue
        candidates.append(
            ClosedListCandidate(
                text.count("\n", 0, match.start()) + 1,
                _normalise_values(values),
            )
        )
    return candidates


def _python_candidate_values(nodes: list[ast.expr]) -> str:
    return ", ".join(ast.unparse(node) for node in nodes)


def _python_candidates(text: str, filename: str) -> list[ClosedListCandidate]:
    tree = ast.parse(text, filename=filename)
    candidates: set[ClosedListCandidate] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Subscript):
            owner = node.value
            is_literal = isinstance(owner, ast.Name) and owner.id == "Literal"
            is_literal = is_literal or (
                isinstance(owner, ast.Attribute) and owner.attr == "Literal"
            )
            if is_literal:
                values = (
                    list(node.slice.elts) if isinstance(node.slice, ast.Tuple) else [node.slice]
                )
                candidates.add(ClosedListCandidate(node.lineno, _python_candidate_values(values)))
        elif isinstance(node, ast.Compare):
            for operator, comparator in zip(node.ops, node.comparators, strict=True):
                if isinstance(operator, (ast.In, ast.NotIn)) and isinstance(
                    comparator, (ast.List, ast.Set)
                ):
                    candidates.add(
                        ClosedListCandidate(
                            node.lineno, _python_candidate_values(list(comparator.elts))
                        )
                    )
    return sorted(candidates, key=lambda item: (item.line, item.values))


def _matching_parenthesis(text: str, opening: int) -> int | None:
    depth = 0
    quote: str | None = None
    escaped = False
    for offset in range(opening, len(text)):
        character = text[offset]
        if escaped:
            escaped = False
            continue
        if quote is not None:
            if character == "\\":
                escaped = True
            elif character == quote:
                quote = None
            continue
        if character in {"'", '"'}:
            quote = character
        elif character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
            if depth == 0:
                return offset
    return None


def _prolog_symbol_exists(text: str, symbol: str) -> bool:
    name, separator, arity_text = symbol.rpartition("/")
    if not separator or not arity_text.isdigit() or not name:
        return False
    arity = int(arity_text)
    spellings = (re.escape(name), re.escape("'" + name.replace("'", "''") + "'"))
    # An optional Module: qualifier, because a clause of a seam is written
    # where the seam lives: `seam:foreign_capability(...) :- ...` in a library
    # is one clause of one predicate, and reading only the unqualified spelling
    # made every module-qualified handler unresolvable as evidence.
    head = re.compile(
        rf"^\s*(?:[a-z][A-Za-z0-9_]*\s*:\s*)?(?:{'|'.join(spellings)})\s*\(",
        re.MULTILINE,
    )
    for match in head.finditer(text):
        opening = text.find("(", match.start(), match.end())
        closing = _matching_parenthesis(text, opening)
        if closing is None:
            continue
        tail = text[closing + 1 :].lstrip()
        if not tail.startswith((":-", "-->", ".")):
            continue
        arguments = text[opening + 1 : closing]
        nested = 0
        commas = 0
        quote: str | None = None
        for character in arguments:
            if quote is not None:
                if character == quote:
                    quote = None
            elif character in {"'", '"'}:
                quote = character
            elif character in "([{":
                nested += 1
            elif character in ")]}":
                nested -= 1
            elif character == "," and nested == 0:
                commas += 1
        actual_arity = 0 if not arguments.strip() else commas + 1
        if actual_arity == arity:
            return True
    return False


def _source_symbol_exists(path: Path, symbol: str) -> bool:
    text = path.read_text(encoding="utf-8")
    if path.suffix == ".pl":
        return _prolog_symbol_exists(text, symbol)
    if path.suffix == ".py":
        try:
            tree = ast.parse(text, filename=str(path))
        except SyntaxError:
            return False
        leaf = symbol.rsplit(".", 1)[-1]
        return any(
            isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))
            and node.name == leaf
            for node in ast.walk(tree)
        )
    return False


def _evidence_problem(root: Path, evidence: str) -> str | None:
    evidence_path, separator, location = evidence.rpartition(":")
    if not separator or not evidence_path or not location:
        return f"exemption evidence location {evidence!r} does not resolve"
    resolved_root = root.resolve()
    source = (root / evidence_path).resolve()
    try:
        source.relative_to(resolved_root)
    except ValueError:
        return f"exemption evidence location {evidence!r} does not resolve"
    if not source.is_file():
        return f"exemption evidence location {evidence!r} does not resolve"
    if location.isdigit():
        line_count = len(source.read_text(encoding="utf-8").splitlines())
        if not 1 <= int(location) <= line_count:
            return f"exemption evidence line {evidence!r} is outside 1..{line_count}"
    elif not _source_symbol_exists(source, location):
        return f"exemption evidence symbol {evidence!r} does not exist"
    return None


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
    return _evidence_problem(root, evidence)


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
            text = path.read_text(encoding="utf-8")
            lines = text.splitlines()
            try:
                candidates = (
                    _prolog_candidates(relative, text)
                    if path.suffix == ".pl"
                    else _python_candidates(text, str(relative))
                )
            except SyntaxError as exc:
                findings.append(f"{relative}:{exc.lineno or 1}: cannot scan Python: {exc.msg}")
                continue
            candidate_lines = {candidate.line for candidate in candidates}
            for number, line in enumerate(lines, start=1):
                if EXEMPTION_MARKER not in line:
                    continue
                problem = _annotation_problem(root, line)
                if problem is not None:
                    findings.append(f"{relative}:{number}: {problem}")
                if number + 1 not in candidate_lines:
                    findings.append(
                        f"{relative}:{number}: exemption is not immediately adjacent to a closed list"
                    )
            for candidate in candidates:
                previous = lines[candidate.line - 2] if candidate.line > 1 else ""
                if EXEMPTION_MARKER not in previous:
                    findings.append(
                        f"{relative}:{candidate.line}: closed policy list "
                        f"[{candidate.values}] has no adjacent exemption"
                    )
    return findings


def main() -> int:
    """Print the derived table and fail on any catalog, seam or list finding."""
    try:
        rows, algebra_laws, semirings = runtime_inventory(ROOT)
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        print(f"policy inventory: {exc}")
        return 1

    findings = validate_policy_rows(ROOT, rows)
    findings.extend(validate_algebra_laws(ROOT, algebra_laws, semirings))
    findings.extend(scan_closed_lists(ROOT))
    by_axis = {str(row["axis"]): row for row in rows if "axis" in row}
    for axis, seam in POLICY_SEAMS.items():
        row = by_axis.get(axis)
        if row is not None:
            print(
                f"policy {axis}: knob={row.get('knob')} default={row.get('default')} "
                f"seam={seam.path}"
            )
    for row in algebra_laws:
        for law in row.get("laws", []):
            print(f"algebra law: semiring={row.get('semiring')} law={law}")
    for finding in findings:
        print(finding)
    print(f"policy inventory: {len(rows)} runtime row(s), {len(findings)} finding(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
