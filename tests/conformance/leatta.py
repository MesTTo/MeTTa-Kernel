"""Purpose: check this engine against LeaTTa's semantics corpus, which is the
    arbiter: every file there carries a MEASURED block holding the answers the
    mechanised interpreter printed, verbatim, with the pinned hyperon build it
    was checked against named beside them. Running our engine over the same file
    and diffing those lines turns "LeaTTa is the oracle" from a habit into a
    check. --gate-areas-file turns that into a PER-AREA promise: an area a gate
    file names must have zero differing checkable files right now, and a later
    regression there fails the run; an area it does not name still runs, still
    prints its differences, and can never fail the run on its own.
Assumes:
  - LeaTTa is checked out; with it absent this reports that and exits 0 in
    EVERY mode, including a per-area run that names promoted areas, because it
    lives outside this repository and the CI container that runs check.sh
    never clones it [source: .github/workflows/checks.yml has no LeaTTa
    checkout step]. A promoted area is therefore enforced only on a machine
    that has LeaTTa checked out, never in this repository's CI.
  - tests/conformance/leatta_run.pl prints one answer GROUP per runnable form.
  - a gate-areas file names only areas discover_areas finds under --corpus; an
    unrecognised name is a configuration error, not a silent no-op, so it
    raises rather than gating nothing.
Guarantees:
  - only the bracketed lines of a MEASURED block are compared, and the count of
    lines skipped for being printed output rather than answers is reported, so
    a partial comparison never reads as a full one.
  - a file whose engine run raises or times out is reported as such rather than
    counted as agreeing.
  - every area prints its own block under --gate-areas-file, promoted or not,
    so a REPORT area's failures stay visible in the same run that enforces the
    promoted ones [tested 2026-08-18: tests/conformance/leatta_gate_selftest.py].
Fails when:
  - the flat mode never fails by exit code unless --gate is passed; that is
    still a REPORT surface for a single ad hoc run.
  - the per-area mode fails the run when ANY area named in --gate-areas-file has
    a differing checkable file; an area left out of that file can print any
    number of differences without failing the run
    [tested 2026-08-18: tests/conformance/leatta_gate_selftest.py].
  - asked to enforce a promotion in CI: this lane's oracle lives at a fixed
    local path outside the repository, so absence there is indistinguishable
    from "not yet promoted" and always yields exit 0.
Decides:
  - a promoted area gates on ZERO differing checkable files, not a percentage
    threshold; the existing single-area --gate already committed to that rule
    and the per-area mode reuses it rather than inventing a softer one.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import argparse
import re
from collections import Counter
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


def summarize(corpus: Path, results: list[Comparison], show: int, label: str) -> bool:
    """Print one block of results exactly as every mode always has, and answer
    whether any checkable file in it differs, which is the one bit a caller
    needs to turn a comparison into a GATE or REPORT verdict."""
    checkable = [result for result in results if result.comparable]
    uncheckable = [result for result in results if not result.comparable]
    agreeing = [result for result in checkable if result.agrees]
    differing = [result for result in checkable if not result.agrees]
    unsettled = [result for result in differing if not result.settled]
    status_counts = Counter(
        result.status.rstrip(".") or "(none)" for result in differing)
    status_breakdown = ", ".join(
        f"{name}: {count}" for name, count in sorted(status_counts.items()))
    comparable = sum(len(result.expected) for result in checkable)
    skipped = sum(result.skipped for result in results)

    for result in differing[:show]:
        print(f"{result.path.relative_to(corpus)}: {result.first_difference}")
    if len(differing) > show:
        print(f"... and {len(differing) - show} more differing files")

    print(
        f"\n{label}: {len(agreeing)}/{len(checkable)} checkable files agree, "
        f"{comparable} answer groups compared.\n"
        f"  {len(uncheckable)} files state their MEASURED block as prose and can carry "
        f"no diff\n"
        f"  {len(unsettled)} of the {len(differing)} differing await the arbiter's own "
        f"ruling (an undecided-* status); the rest differ from its commitments\n"
        f"  differing by the arbiter's status: {status_breakdown}\n"
        f"  {skipped} MEASURED lines are printed output rather than answers"
    )
    return bool(differing)


def discover_areas(corpus: Path) -> list[str]:
    """LeaTTa's areas: every immediate subdirectory of the corpus holding at
    least one .metta file, found rather than named, so a tenth area LeaTTa
    adds later is seen here without a code change, and defaults to
    REPORT until a gate-areas file promotes it."""
    return sorted(
        child.name
        for child in corpus.iterdir()
        if child.is_dir() and next(child.rglob("*.metta"), None) is not None
    )


def read_gated_areas(path: Path, known: list[str]) -> set[str]:
    """The area names a gate-areas file promotes to GATE.

    One name per line; '#' starts a comment, inline or whole-line; blank lines
    are ignored. A name this corpus does not have is a configuration error and
    raises, rather than silently gating nothing: a typo that failed to gate
    anything would be worse than the typo being loud.
    """
    if not path.is_file():
        raise SystemExit(f"leatta: no gate-areas file at {path}")
    gated: set[str] = set()
    for line in path.read_text().splitlines():
        name = line.split("#", 1)[0].strip()
        if name:
            gated.add(name)
    unknown = gated - set(known)
    if unknown:
        raise SystemExit(
            f"leatta: {path} names unknown area(s) {sorted(unknown)}; "
            f"known areas are {known}"
        )
    return gated


def main_per_area(arguments: argparse.Namespace) -> int:
    """Run every area, print every area, and fail the run only for a
    promoted one that currently disagrees somewhere."""
    areas = discover_areas(arguments.corpus)
    gated = read_gated_areas(arguments.gate_areas_file, areas)

    regressed = []
    for area in areas:
        files = sorted((arguments.corpus / area).rglob("*.metta"))
        results = [compare(arguments.engine, path, arguments.timeout) for path in files]
        tier = "GATE" if area in gated else "REPORT"
        has_diff = summarize(
            arguments.corpus, results, arguments.show,
            f"LeaTTa conformance [{area}, {tier}]",
        )
        if tier == "GATE" and has_diff:
            regressed.append(area)

    print(f"\n{len(gated)}/{len(areas)} areas promoted to GATE: {sorted(gated) or 'none'}")
    if regressed:
        print(f"regressed: {regressed}")
    else:
        print("every promoted area conforms")
    return 1 if regressed else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, default=CORPUS)
    parser.add_argument("--engine", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("--area", default="", help="only files under this subdirectory")
    parser.add_argument("--show", type=int, default=25, help="how many differences to print")
    parser.add_argument("--gate", action="store_true", help="exit nonzero on any difference")
    parser.add_argument(
        "--gate-areas-file",
        type=Path,
        default=None,
        help="promote the areas this file lists to GATE; every other area stays REPORT",
    )
    arguments = parser.parse_args(argv)

    if not arguments.corpus.is_dir():
        print(f"LeaTTa corpus not found at {arguments.corpus}; nothing to check")
        return 0

    if arguments.gate_areas_file is not None:
        if arguments.area or arguments.gate:
            raise SystemExit("leatta: --gate-areas-file replaces --area and --gate, not both")
        return main_per_area(arguments)

    root = arguments.corpus / arguments.area if arguments.area else arguments.corpus
    files = sorted(path for path in root.rglob("*.metta"))
    if not files:
        print(f"no .metta files under {root}")
        return 0

    results = [compare(arguments.engine, path, arguments.timeout) for path in files]
    has_diff = summarize(arguments.corpus, results, arguments.show, "LeaTTa conformance")
    return 1 if (arguments.gate and has_diff) else 0


if __name__ == "__main__":
    raise SystemExit(main())
