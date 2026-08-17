"""Purpose: check this engine against LeaTTa's semantics corpus, which is the
    arbiter: every file there carries a MEASURED block holding the answers the
    mechanised interpreter printed, verbatim, with the pinned hyperon build it
    was checked against named beside them. Running our engine over the same file
    and diffing those lines turns "LeaTTa is the oracle" from a habit into a
    check.
Assumes:
  - LeaTTa is checked out; with it absent this reports that and exits 0, the
    way an optional tool should, because it lives outside this repository.
  - tests/conformance/leatta_run.pl prints one answer GROUP per runnable form.
Guarantees:
  - only the bracketed lines of a MEASURED block are compared, and the count of
    lines skipped for being printed output rather than answers is reported, so
    a partial comparison never reads as a full one.
  - a file whose engine run raises or times out is reported as such rather than
    counted as agreeing.
Fails when:
  - never by exit code unless --gate is passed. This is a REPORT surface while
    its backlog is open, which is how every other burn-down check here starts.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

CORPUS = Path("/home/user/Dev/LeaTTa/tests/semantics")
ANSWER = "LEATTA-ANSWER "
FAILURE = "LEATTA-ERROR "
MEASURED = re.compile(r"^;\s*MEASURED:")
STATUS = re.compile(r"^;\s*STATUS:\s*(.*)$")
BRACKETED = re.compile(r"^;\s+\[(.*)\]\s*$")
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
        """Whether the arbiter itself claims to have settled this behaviour."""
        return self.status.startswith("conforms")

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
    appears bare and an answer appears bracketed. Only the second kind is an
    answer group, and the first kind is counted rather than ignored.
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
        bracketed = BRACKETED.match(line)
        if bracketed:
            groups.append(canonical(f"[{bracketed.group(1)}]"))
            continue
        body = COMMENT.match(line)
        if body and body.group(1).strip():
            skipped += 1
    return groups, skipped


def observe(engine: Path, path: Path, timeout: float) -> tuple[list[str], str | None]:
    """Run one file and read its answer groups back."""
    try:
        finished = subprocess.run(
            [
                "swipl", "--stack_limit=8g", "-q",
                "-g", f'consult("{engine}/src/metta.pl")',
                "-s", str(engine / "tests/conformance/leatta_run.pl"),
                "--", "--file", str(path), "backends",
            ],
            capture_output=True, text=True, timeout=timeout, cwd=engine,
        )
    except subprocess.TimeoutExpired:
        return [], f"timed out after {timeout:g}s"
    groups: list[str] = []
    for line in finished.stdout.splitlines():
        if line.startswith(ANSWER):
            groups.append(canonical(line[len(ANSWER):]))
        elif line.startswith(FAILURE):
            return groups, line[len(FAILURE):].strip()
    return groups, None


def declared_status(source: str) -> str:
    """The arbiter's own verdict on the file, which is not always "conforms"."""
    for line in source.splitlines():
        matched = STATUS.match(line)
        if matched:
            return matched.group(1).strip()
    return ""


def compare(engine: Path, path: Path, timeout: float) -> Comparison:
    source = path.read_text(errors="replace")
    expected, skipped = expected_groups(source)
    status = declared_status(source)
    if not expected:
        return Comparison(path, expected, [], skipped, None, status)
    observed, error = observe(engine, path, timeout)
    return Comparison(path, expected, observed, skipped, error, status)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, default=CORPUS)
    parser.add_argument("--engine", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("--area", default="", help="only files under this subdirectory")
    parser.add_argument("--show", type=int, default=25, help="how many differences to print")
    parser.add_argument("--gate", action="store_true", help="exit nonzero on any difference")
    arguments = parser.parse_args(argv)

    if not arguments.corpus.is_dir():
        print(f"LeaTTa corpus not found at {arguments.corpus}; nothing to check")
        return 0

    root = arguments.corpus / arguments.area if arguments.area else arguments.corpus
    files = sorted(path for path in root.rglob("*.metta"))
    if not files:
        print(f"no .metta files under {root}")
        return 0

    results = [compare(arguments.engine, path, arguments.timeout) for path in files]
    checkable = [result for result in results if result.comparable]
    uncheckable = [result for result in results if not result.comparable]
    agreeing = [result for result in checkable if result.agrees]
    differing = [result for result in checkable if not result.agrees]
    unsettled = [result for result in differing if not result.settled]
    comparable = sum(len(result.expected) for result in checkable)
    skipped = sum(result.skipped for result in results)

    for result in differing[: arguments.show]:
        print(f"{result.path.relative_to(arguments.corpus)}: {result.first_difference}")
    if len(differing) > arguments.show:
        print(f"... and {len(differing) - arguments.show} more differing files")

    print(
        f"\nLeaTTa conformance: {len(agreeing)}/{len(checkable)} checkable files agree, "
        f"{comparable} answer groups compared.\n"
        f"  {len(uncheckable)} files state their MEASURED block as prose and can carry "
        f"no diff\n"
        f"  {len(unsettled)} of the {len(differing)} differing are on behaviour the "
        f"arbiter itself has not settled\n"
        f"  {skipped} MEASURED lines are printed output rather than answers"
    )
    return 1 if (arguments.gate and differing) else 0


if __name__ == "__main__":
    raise SystemExit(main())
