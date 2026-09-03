"""Purpose: hold KERNEL.md's translator roster and counts to the running engine.

KERNEL.md is a reason ledger, not a second implementation of the translator.
The engine therefore supplies the two rosters: clause heads from
``metta_special_form_head/1`` and the prelude rules registered through
``translator_rule/3``. The document supplies only the classification and why
each head remains where it is.

The classification is DERIVED FROM THE CODE, not maintained by hand. A head
added to either runtime roster fails here until KERNEL.md gives it a row; a
removed head makes its old row fail in the other direction.

Assumes:
  - swipl is on PATH and the built engine boots from the repository root.
Guarantees:
  - the opening total, special-head count, special-clause count, prelude-rule
    count, implementation source and table headings equal the running engine [tested:
    tests/checks/check_kernel_ledger_selftest.py; commit=WORKTREE]
  - every runtime head has exactly one row in its corresponding table and no
    stale row survives; every special row states a kind and reason [tested:
    tests/checks/check_kernel_ledger_selftest.py; commit=WORKTREE]
Fails when:
  - the engine cannot boot or its query emits an unrecognised record; neither
    state can turn an unread ledger green.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None.
"""

from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PAGE = ROOT / "KERNEL.md"

_QUERY = (
    "ensure_loaded('engine/qlf_boot.pl'), "
    "ensure_loaded('engine/metta.pl'), "
    "findall(H, translator:metta_special_form_head(H), Hs0), "
    "sort(Hs0, Hs), "
    "aggregate_all(count, "
    "clause(translator:translate_special_dl(_,_,_,_,_), _), Clauses), "
    "findall(R, translator_rule(R,_,_), Rs0), "
    "sort(Rs0, Rs), "
    "length(Hs, HCount), length(Rs, RCount), "
    "Total is HCount+RCount, "
    "predicate_property(translator:translate_special_dl(_,_,_,_,_), "
    "file(Source)), "
    "format('COUNTS\\t~d\\t~d\\n', [Clauses, Total]), "
    "format('SOURCE\\t~w\\n', [Source]), "
    "forall(member(H, Hs), format('SPECIAL\\t~w\\n', [H])), "
    "forall(member(R, Rs), format('PRELUDE\\t~w\\n', [R]))"
)

_COUNT_CLAIMS = {
    "total heads": (
        re.compile(r"The translator gives (?P<count>\d+) heads a meaning"),
        lambda inventory: inventory.total_heads,
    ),
    "special heads": (
        re.compile(r"(?P<count>\d+) of them are clauses\s+of `translate_special_dl/5`"),
        lambda inventory: len(inventory.special_heads),
    ),
    "special clauses": (
        re.compile(r"(?P<count>\d+) clauses\s+over those \d+\s+heads"),
        lambda inventory: inventory.special_clauses,
    ),
    "prelude rules": (
        re.compile(r"the remaining (?P<count>\d+) are equations"),
        lambda inventory: len(inventory.prelude_heads),
    ),
    "special-table heading": (
        re.compile(r"## `translate_special_dl/5`, (?P<count>\d+) heads"),
        lambda inventory: len(inventory.special_heads),
    ),
    "prelude-table heading": (
        re.compile(r"## The prelude's derived forms, (?P<count>\d+) heads"),
        lambda inventory: len(inventory.prelude_heads),
    ),
}

_SOURCE_CLAIM = re.compile(r"clauses\s+of `translate_special_dl/5` in `(?P<path>[^`]+)`")

_SPECIAL_SECTION = re.compile(
    r"## `translate_special_dl/5`, \d+ heads\n(?P<body>.*?)"
    r"\n## The prelude's derived forms,",
    re.DOTALL,
)
_PRELUDE_SECTION = re.compile(
    r"## The prelude's derived forms, \d+ heads\n(?P<body>.*?)"
    r"\n## What fusing a head costs",
    re.DOTALL,
)
_SPECIAL_ROW = re.compile(
    r"^\| `(?P<head>[^`]+)` \| (?P<kind>[^|]+?) \| (?P<reason>.+?) \|$",
    re.MULTILINE,
)
_PRELUDE_ROW = re.compile(
    r"^\| `(?P<head>[^`]+)` \| (?P<expansion>.+?) \| (?P<measured>.+?) \|$",
    re.MULTILINE,
)


@dataclass(frozen=True)
class Inventory:
    """The two live translator rosters and the clause count behind them."""

    special_heads: frozenset[str]
    prelude_heads: frozenset[str]
    special_clauses: int
    special_source: str

    @property
    def total_heads(self) -> int:
        """Distinct heads across the fused and prelude tiers."""
        return len(self.special_heads | self.prelude_heads)


class KernelLedgerError(RuntimeError):
    """The runtime inventory could not be read without guessing."""


def engine_inventory(root: Path = ROOT) -> Inventory:
    """Ask one engine process for the live KERNEL.md roster."""
    completed = subprocess.run(
        ["swipl", "-q", "-g", _QUERY, "-t", "halt"],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "no diagnostic"
        message = f"swipl KERNEL.md query exited {completed.returncode}: {detail}"
        raise KernelLedgerError(message)

    special: set[str] = set()
    prelude: set[str] = set()
    clauses: int | None = None
    reported_total: int | None = None
    source: str | None = None
    for line in completed.stdout.splitlines():
        tag, separator, payload = line.partition("\t")
        if not separator:
            message = f"swipl KERNEL.md query emitted an untagged line: {line!r}"
            raise KernelLedgerError(message)
        if tag == "SPECIAL":
            special.add(payload)
        elif tag == "PRELUDE":
            prelude.add(payload)
        elif tag == "COUNTS":
            fields = payload.split("\t")
            if len(fields) != 2 or any(not field.isdecimal() for field in fields):
                message = f"swipl KERNEL.md query emitted malformed counts: {line!r}"
                raise KernelLedgerError(message)
            clauses, reported_total = map(int, fields)
        elif tag == "SOURCE":
            try:
                source = str(Path(payload).resolve().relative_to(root.resolve()))
            except ValueError as error:
                message = f"swipl KERNEL.md query reported a source outside the tree: {payload!r}"
                raise KernelLedgerError(message) from error
        else:
            message = f"swipl KERNEL.md query emitted unknown tag: {tag!r}"
            raise KernelLedgerError(message)
    if clauses is None or reported_total is None or source is None:
        message = "swipl KERNEL.md query omitted its COUNTS or SOURCE record"
        raise KernelLedgerError(message)
    inventory = Inventory(frozenset(special), frozenset(prelude), clauses, source)
    if reported_total != len(special) + len(prelude):
        message = (
            "swipl KERNEL.md query's total disagrees with its emitted rosters: "
            f"{reported_total} != {len(special)} + {len(prelude)}"
        )
        raise KernelLedgerError(message)
    return inventory


def _rows(
    text: str,
    section_pattern: re.Pattern[str],
    row_pattern: re.Pattern[str],
) -> tuple[dict[str, tuple[str, str]], list[str]]:
    section = section_pattern.search(text)
    if section is None:
        return {}, []
    rows: dict[str, tuple[str, str]] = {}
    duplicates: list[str] = []
    for match in row_pattern.finditer(section.group("body")):
        head = match.group("head").replace(r"\|", "|")
        values = (match.group(2).strip(), match.group(3).strip())
        if head in rows:
            duplicates.append(head)
        else:
            rows[head] = values
    return rows, duplicates


def findings(text: str, inventory: Inventory) -> list[str]:
    """Return every count, roster, classification, and reason mismatch."""
    problems: list[str] = []
    overlap = inventory.special_heads & inventory.prelude_heads
    if overlap:
        problems.append("the engine publishes heads in both tiers: " + ", ".join(sorted(overlap)))

    for label, (pattern, expected_from) in _COUNT_CLAIMS.items():
        match = pattern.search(text)
        if match is None:
            problems.append(f"KERNEL.md no longer states its {label} count")
            continue
        stated = int(match.group("count"))
        expected = expected_from(inventory)
        if stated != expected:
            problems.append(f"KERNEL.md says {stated} {label}; the engine says {expected}")

    source_claim = _SOURCE_CLAIM.search(text)
    if source_claim is None:
        problems.append("KERNEL.md no longer states the special-form implementation source")
    elif source_claim.group("path") != inventory.special_source:
        problems.append(
            "KERNEL.md says special forms live in "
            f"{source_claim.group('path')}; the engine says {inventory.special_source}"
        )

    special_rows, special_duplicates = _rows(text, _SPECIAL_SECTION, _SPECIAL_ROW)
    prelude_rows, prelude_duplicates = _rows(text, _PRELUDE_SECTION, _PRELUDE_ROW)
    problems.extend(
        f"KERNEL.md gives special head `{head}` more than one row" for head in special_duplicates
    )
    problems.extend(
        f"KERNEL.md gives prelude head `{head}` more than one row" for head in prelude_duplicates
    )
    problems.extend(
        f"engine special head `{head}` has no KERNEL.md row"
        for head in sorted(inventory.special_heads - set(special_rows))
    )
    problems.extend(
        f"KERNEL.md special row `{head}` names no engine special head"
        for head in sorted(set(special_rows) - inventory.special_heads)
    )
    problems.extend(
        f"engine prelude rule `{head}` has no KERNEL.md row"
        for head in sorted(inventory.prelude_heads - set(prelude_rows))
    )
    problems.extend(
        f"KERNEL.md prelude row `{head}` names no registered translator rule"
        for head in sorted(set(prelude_rows) - inventory.prelude_heads)
    )
    for head, (kind, reason) in sorted(special_rows.items()):
        if not (kind.startswith("core, ") or kind == "derived, fused"):
            problems.append(f"KERNEL.md row `{head}` has no recognised core/derived kind: {kind!r}")
        if not reason.strip():
            problems.append(f"KERNEL.md row `{head}` gives no reason")
    for head, (expansion, measured) in sorted(prelude_rows.items()):
        if not expansion.strip():
            problems.append(f"KERNEL.md prelude row `{head}` gives no expansion")
        if not measured.strip():
            problems.append(f"KERNEL.md prelude row `{head}` gives no measurement")
    return problems


def main() -> int:
    """Compare the checked-in ledger with the running engine."""
    try:
        inventory = engine_inventory()
        problems = findings(PAGE.read_text(encoding="utf-8"), inventory)
    except (OSError, KernelLedgerError) as error:
        print(f"kernel-ledger: {error}", file=sys.stderr)
        return 1
    for problem in problems:
        print(problem, file=sys.stderr)
    print(
        "kernel-ledger: "
        f"{inventory.total_heads} heads "
        f"({len(inventory.special_heads)} special across "
        f"{inventory.special_clauses} clauses, "
        f"{len(inventory.prelude_heads)} prelude), "
        f"{len(problems)} finding(s)"
    )
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
