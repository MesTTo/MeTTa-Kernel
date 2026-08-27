"""Purpose: check the example corpus's cumulative-syntax law.

The law: a file may use only constructs introduced at or before its own number.

The introduction table is CHECKED IN, at tests/data/syntax_introductions.txt,
and that is the whole point. Derived on the fly the law is vacuous, because
"introduced" would mean "first used" and every use would satisfy it by
construction. Held as data, the same law catches a file moved earlier than the
construct it needs, a construct reaching a chapter before the one that teaches
it, and a table row that no longer matches the corpus. It is the shape
eslint-plugin-es-x and @eslint/css's require-baseline use for the same problem
in another language: a feature-to-availability table beside the code, a target
per file, and a lint that compares them.

Assumes:
  - swipl is on PATH and tests/prolog/example_constructs.pl is the scanner,
    which reads through the engine's own parser and filters against the
    engine's own vocabulary
  - an example's coordinate is its path: examples/chNN-slug/[NN-SS-slug/]II-leaf,
    a directory whose name starts with `_` being the chapter's own level
Guarantees:
  - a use before its introduction, an unknown construct, a stale or misplaced
    table row, a row naming something the language does not have, and a
    dependency inversion each fail independently
    [tested: tests/checks/check_cumulative_syntax_selftest.py]
  - the permanent negative control at
    examples/ch01-getting-started/_fixtures/01-reaches-forward.metta must be
    caught on every run, so a lane that has stopped checking fails instead of
    reporting a green it did not earn
    [tested: tests/checks/check_cumulative_syntax_selftest.py]
  - --write regenerates the table from the corpus, and what it writes is what
    the check reads back, `#`-prefixed construct names included
    [tested: tests/checks/check_cumulative_syntax_selftest.py]
Decides:
  - the vocabulary is the engine's, builtin_fun/1 and metta_special_form_head/1
    plus `!`; `:` and `->` are type-declaration syntax the engine publishes as
    neither, so the law does not reach them
"""

from __future__ import annotations

import argparse
import collections
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCANNER_DIRECTORY = ROOT / "tests" / "prolog"
SCANNER = "example_constructs.pl"
TABLE = ROOT / "tests" / "data" / "syntax_introductions.txt"
CONTROL = "examples/ch01-getting-started/_fixtures/01-reaches-forward.metta"
FIXTURE_MARKER = "_fixtures"

Coordinate = tuple[int, int, int]

TABLE_HEADER = """\
;Every construct the example corpus uses, and the example that introduces it.
;
;The law this serves: a file may use only constructs introduced at or before
;its own number. tests/checks/check_cumulative_syntax.py checks it against
;THIS file rather than against the corpus, because a table derived from the
;corpus makes the law true by definition and catches nothing. Held here, it
;catches a file moved earlier than the construct it needs, a construct
;reaching a chapter before the one that teaches it, and a row this corpus no
;longer supports.
;
;A coordinate is CHAPTER-SECTION-INDEX, read from the example's own path;
;section 00 is a file that sits directly in its chapter's directory. Rows are
;in teaching order, so reading down is reading the order a learner meets them.
;
;The comment character is MeTTa's `;` rather than `#`, because `#*`, `#+`,
;`#<` and the rest of the relational arithmetic family are construct NAMES
;and a `#` reader silently swallowed all fifteen of their rows.
;
;Regenerate with `python tests/checks/check_cumulative_syntax.py --write`
;after a deliberate change to that order, and read the diff: it says exactly
;which construct moved and where to.
;
;construct                        introduced
"""


def coordinate(path: str) -> Coordinate:
    """(chapter, section, index) for one example path.

    A file directly in `chNN-slug/` and a file in that chapter's `_fixtures/`
    are both at section 00: a chapter's fixtures belong to the chapter, and
    only a numbered `NN-SS-slug/` directory is a section of its own.
    """
    parts = Path(path).parts
    at = parts.index("examples")
    chapter = int(parts[at + 1][2:4])
    rest = parts[at + 2 :]
    if len(rest) == 1:
        return (chapter, 0, int(rest[0][:2]))
    section = 0 if rest[0].startswith("_") else int(rest[0].split("-")[1])
    return (chapter, section, int(rest[-1][:2]))


def spell(coord: Coordinate) -> str:
    """A coordinate as it is written in the table and in a finding."""
    chapter, section, index = coord
    return f"{chapter:02d}-{section:02d}-{index:02d}"


def read_coordinate(text: str) -> Coordinate:
    """The inverse of spell, for a table row."""
    chapter, section, index = text.split("-")
    return (int(chapter), int(section), int(index))


def run_scanner(*arguments: str) -> str:
    """The scanner's stdout, run from tests/prolog as every Prolog gate is."""
    finished = subprocess.run(  # noqa: S603 -- the argument vector is this file's own
        ["swipl", SCANNER, *arguments],  # noqa: S607 -- swipl is on PATH for every Prolog lane
        cwd=SCANNER_DIRECTORY,
        capture_output=True,
        text=True,
        check=True,
    )
    return finished.stdout


def scan(paths: list[str]) -> dict[str, set[str]]:
    """Every construct each path uses, keyed by path relative to the root."""
    relative = [str(Path("../..") / path) for path in paths]
    used: dict[str, set[str]] = {path: set() for path in paths}
    for line in run_scanner(*relative).splitlines():
        scanned, name = line.split("\t")
        used[str(Path(scanned).relative_to("../.."))].add(name)
    return used


def vocabulary() -> set[str]:
    """Every construct name the engine publishes."""
    return {
        line.split("\t")[1]
        for line in run_scanner("--vocabulary").splitlines()
    }


def corpus_paths() -> list[str]:
    """Every example the law covers: the whole corpus but its fixtures."""
    return sorted(
        str(path.relative_to(ROOT))
        for path in (ROOT / "examples").rglob("*.metta")
        if FIXTURE_MARKER not in path.parts
    )


def read_table(text: str) -> dict[str, Coordinate]:
    """The checked-in introduction table."""
    table = {}
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith(";"):
            continue
        name, where = stripped.split()
        table[name] = read_coordinate(where)
    return table


def derive_table(used: dict[str, set[str]]) -> dict[str, Coordinate]:
    """The table this corpus implies: each construct at its earliest use."""
    earliest: dict[str, Coordinate] = {}
    for path, names in used.items():
        coord = coordinate(path)
        for name in names:
            if name not in earliest or coord < earliest[name]:
                earliest[name] = coord
    return earliest


def write_table(used: dict[str, set[str]]) -> str:
    """The table file's whole text, in teaching order."""
    rows = sorted(derive_table(used).items(), key=lambda row: (row[1], row[0]))
    body = "".join(f"{name:<33} {spell(coord)}\n" for name, coord in rows)
    return TABLE_HEADER + body


def law_findings(
    used: dict[str, set[str]], table: dict[str, Coordinate]
) -> list[str]:
    """Uses that reach forward, and uses of constructs the table lacks."""
    findings = []
    for path in sorted(used):
        coord = coordinate(path)
        for name in sorted(used[path]):
            if name == "?PARSE-ERROR":
                findings.append(f"{path}: does not parse, so nothing was checked")
            elif name not in table:
                findings.append(
                    f"{path}: uses {name}, which has no row in "
                    f"{TABLE.relative_to(ROOT)}"
                )
            elif table[name] > coord:
                findings.append(
                    f"{path} is {spell(coord)} and uses {name}, "
                    f"introduced at {spell(table[name])}"
                )
    return findings


def table_findings(
    used: dict[str, set[str]], table: dict[str, Coordinate], known: set[str]
) -> list[str]:
    """Rows the corpus no longer supports, and rows naming a non-construct."""
    derived = derive_table(used)
    findings = []
    for name in sorted(table):
        if name not in known:
            findings.append(
                f"{name} has a row but is not a construct the engine publishes"
            )
        elif name not in derived:
            findings.append(f"{name} has a row but no example uses it")
        elif derived[name] != table[name]:
            findings.append(
                f"{name} is introduced at {spell(derived[name])} "
                f"but its row says {spell(table[name])}"
            )
    return findings


def dependency_findings(
    used: dict[str, set[str]], table: dict[str, Coordinate]
) -> list[str]:
    """The spine's measured floor, recomputed and applied to the order.

    A sits above B when EVERY file using A also uses B and B is more common,
    which makes B something A never appears without. A chapter may not come
    before its constructs' requirements, so B's introduction may not be later
    than A's. This is the one rule here that the corpus can genuinely violate:
    the other two compare the table with the tree, while this compares the
    ORDER with a relation measured from the programs themselves.
    """
    files: dict[str, set[str]] = collections.defaultdict(set)
    for path, names in used.items():
        for name in names:
            files[name].add(path)
    findings = []
    for above in sorted(files):
        for below in sorted(files):
            if above == below or len(files[below]) <= len(files[above]):
                continue
            if not files[above] <= files[below]:
                continue
            # A construct with no row is already a finding of its own; giving
            # it a coordinate here would invent one and read as "introduced
            # first", which is the answer that hides the inversion.
            if above not in table or below not in table:
                continue
            if table[below] > table[above]:
                findings.append(
                    f"{above} never appears without {below}, but {above} is "
                    f"introduced at {spell(table[above])} and {below} at "
                    f"{spell(table[below])}"
                )
    return findings


def control_findings(
    control: dict[str, set[str]], table: dict[str, Coordinate]
) -> list[str]:
    """Whether the permanent negative control is still caught."""
    if law_findings(control, table):
        return []
    return [
        f"the negative control {CONTROL} was not caught; the lane is not "
        f"checking anything and its green means nothing"
    ]


def main(argv: list[str] | None = None) -> int:
    """Check the law, or rewrite the table the law is checked against."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--write",
        action="store_true",
        help="regenerate the introduction table from the corpus",
    )
    arguments = parser.parse_args(argv)

    paths = corpus_paths()
    scanned = scan([*paths, CONTROL])
    used = {path: scanned[path] for path in paths}
    control = {CONTROL: scanned[CONTROL]}

    if arguments.write:
        TABLE.write_text(write_table(used), encoding="utf-8")
        print(f"wrote {TABLE.relative_to(ROOT)}: {len(derive_table(used))} constructs")
        return 0

    table = read_table(TABLE.read_text(encoding="utf-8"))
    findings = law_findings(used, table)
    findings += table_findings(used, table, vocabulary())
    findings += dependency_findings(used, table)
    findings += control_findings(control, table)
    for finding in findings:
        print(finding)
    print(
        f"cumulative syntax: {len(paths)} example(s), {len(table)} construct(s), "
        f"negative control at {CONTROL}, {len(findings)} finding(s)"
    )
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
