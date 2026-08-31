"""Purpose: read a MEASURED-block corpus. A file in this format states, in
its own comments, the answer groups a reference printed for it and whether it
is expected to agree, and this module turns that back into data.

The format is the semantics corpus tests/conformance/cetta.py replays through
the C fork. It lived in tests/conformance/leatta.py until 2026-08-30, when
that lane retired: PeTTa is the semantics arbiter now and
tests/conformance/petta.py is the gate that says so. The FORMAT is not an
arbiter claim, so it moves here with its one remaining reader rather than
leaving the two-runtime differential without a corpus.

Assumes:
  - the corpus lives outside this repository; LEATTA_PATH names that
    checkout and CORPUS derives the default from it, the same override
    extensions/python/tests/conformance/test_critical_pair_oracle.py reads,
    so no tracked file spells an absolute workspace path.
Guarantees:
  - a group compares as a space-separated sequence whichever side wrote it,
    with quotes dropped, which is stated as a limitation below rather than
    hidden.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None.
"""  # noqa: D205  -- the scenario narrative is one continuous invariant, not summary-and-body prose

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path

#: Anchored to this file rather than to the working directory, and beside
#: the repository rather than inside it, which is where the sibling
#: checkouts live. LEATTA_PATH overrides it, the same name
#: test_critical_pair_oracle.py reads.
_SIBLING = Path(__file__).resolve().parents[4] / "LeaTTa"

CORPUS = Path(os.environ.get("LEATTA_PATH", _SIBLING)) / "tests" / "semantics"

ANSWER = "LEATTA-ANSWER "

FAILURE = "LEATTA-ERROR "

MEASURED = re.compile(r"^;\s*MEASURED:")

STATUS = re.compile(r"^;\s*STATUS:\s*(.*)$")

BRACKETED = re.compile(r"^;\s+\[(.*)\]\s*$")

PRODUCED_VERBATIM = re.compile(r"^;\s+produced verbatim `(\[.*\])`\.\s*$")

COMMENT = re.compile(r"^;\s?(.*)$")

@dataclass
class Comparison:
    """One file's verdict, and enough to say why."""

    path: Path
    expected: list[str]
    observed: list[str]
    skipped: int
    error: str | None
    status: str

    @property
    def comparable(self) -> bool:
        """Whether this file states a machine-checkable expectation at all.

        A MEASURED block may be prose ("the marker occurred once"), which is a
        real record and not one a diff can read. Counting those as differences
        would inflate the number with files that never disagreed with anything,
        and a helper module imported by a sibling is usually one of them.
        """
        return bool(self.expected)

    @property
    def settled(self) -> bool:
        """Whether the arbiter has committed to this behaviour.

        The arbiter's word is the definition, so conforms, diverges and
        ours are all commitments: a diverges file is the arbiter RULING
        against upstream, and a difference against it is engine backlog.
        Only an undecided-* status still awaits the arbiter's own ruling.
        """
        return not self.status.startswith("undecided")

    @property
    def agrees(self) -> bool:
        return self.error is None and self.expected == self.observed

    @property
    def first_difference(self) -> str:
        if self.error:
            return self.error
        for index, (want, got) in enumerate(zip(self.expected, self.observed)):
            if want != got:
                return f"line {index + 1}: expected {want}  observed {got}"
        if len(self.expected) != len(self.observed):
            return (
                f"{len(self.expected)} expected answer groups, "
                f"{len(self.observed)} observed"
            )
        return ""


def canonical(group: str) -> str:
    """A group as a space-separated sequence, whichever side wrote it.

    Quotes are dropped, and that is a real limitation rather than a tidy-up:
    the arbiter's writer prints a string bare, so its record of an error
    message reads `... expects a space as the first argument` where this engine
    writes `"... expects a space as the first argument"`. Nothing in the corpus
    distinguishes a string from a sequence of symbols, so neither can this
    comparison. A divergence where one side answers a STRING and the other the
    same text as symbols is therefore invisible here.
    """
    inner = group.strip().replace('"', "")
    if inner[:1] in "([" and inner[-1:] in ")]":
        inner = inner[1:-1]
    return " ".join(part.strip() for part in split_top_level(inner) if part.strip())



def expected_groups(source: str) -> tuple[list[str], int]:
    """The MEASURED block's answer groups, and how many lines were not groups.

    A MEASURED block interleaves printed output with answers: a `println!` line
    appears bare and an answer normally appears bracketed. Seven arbiter files
    instead state one answer in the exact form `produced verbatim `[...].`;
    that strict form is also an answer, while every other prose line is counted.
    """
    groups: list[str] = []
    skipped = 0
    inside = False
    for line in source.splitlines():
        if MEASURED.match(line):
            inside = True
            continue
        if not inside:
            continue
        if STATUS.match(line) or not line.startswith(";"):
            break
        produced = PRODUCED_VERBATIM.match(line)
        if produced:
            groups.append(canonical(produced.group(1)))
            continue
        bracketed = BRACKETED.match(line)
        if bracketed:
            groups.append(canonical(f"[{bracketed.group(1)}]"))
            continue
        body = COMMENT.match(line)
        if body and body.group(1).strip():
            skipped += 1
    return groups, skipped



def declared_status(source: str) -> str:
    """The arbiter's own verdict on the file, which is not always "conforms"."""
    for line in source.splitlines():
        matched = STATUS.match(line)
        if matched:
            return matched.group(1).strip()
    return ""


def split_top_level(text: str) -> list[str]:
    """Split `a, (b, c), "d, e"` on its TOP-LEVEL commas only.

    LeaTTa writes a group as `[a, b]` and this engine writes `(a b)`, so the
    separator has to be normalised before the two can be compared. Splitting on
    every comma would cut inside a nested group and inside a string literal.
    """
    parts: list[str] = []
    depth = 0
    quoted = False
    escaped = False
    current: list[str] = []
    index = 0
    while index < len(text):
        character = text[index]
        if escaped:
            escaped = False
        elif character == "\\" and quoted:
            escaped = True
        elif character == '"':
            quoted = not quoted
        elif not quoted and character in "([":
            depth += 1
        elif not quoted and character in ")]":
            depth -= 1
        elif not quoted and depth == 0 and character == "," and text[index : index + 2] == ", ":
            parts.append("".join(current))
            current = []
            index += 2
            continue
        current.append(character)
        index += 1
    if current or parts:
        parts.append("".join(current))
    return parts
