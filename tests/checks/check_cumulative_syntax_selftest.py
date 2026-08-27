"""Purpose: prove the cumulative-syntax gate turns planted violations red.

Guarantees:
  - a forward reference, a construct with no row, a file that does not parse, a
    stale row, a misplaced row, a row naming a non-construct, a dependency
    inversion and an uncaught negative control each fail independently, while
    the consistent fixture passes
    [tested: tests/checks/check_cumulative_syntax_selftest.py]
  - a `#`-prefixed construct keeps its row, the reason the table's comment
    character is `;`: the fifteen relational arithmetic names begin with the
    character every other table in this tree comments with, and a `#` reader
    dropped all of them silently
    [tested: tests/checks/check_cumulative_syntax_selftest.py]
"""

from __future__ import annotations

import sys

from check_cumulative_syntax import (
    control_findings,
    coordinate,
    dependency_findings,
    law_findings,
    read_table,
    table_findings,
    write_table,
)

# A miniature corpus: two chapter-1 files that use only `+` and `test`, and one
# chapter-7 file that also uses `if`. `+` and `test` are therefore things `if`
# never appears without, which is the dependency relation the spine measured.
USED = {
    "examples/ch01-getting-started/01-hello.metta": {"!", "+"},
    "examples/ch01-getting-started/02-checking.metta": {"!", "+", "test"},
    "examples/ch07-control-flow/07-01-if/01-if.metta": {"!", "+", "test", "if"},
}
TABLE = {
    "!": (1, 0, 1),
    "+": (1, 0, 1),
    "test": (1, 0, 2),
    "if": (7, 1, 1),
}
KNOWN = {"!", "+", "test", "if", "hyperpose"}
CONTROL = {"examples/ch01-getting-started/_fixtures/01-reaches-forward.metta": {"if"}}


def all_findings(
    used=None, table=None, known=None, control=None
) -> list[str]:
    """Every rule the gate applies, over one fixture."""
    used = USED if used is None else used
    table = TABLE if table is None else table
    known = KNOWN if known is None else known
    control = CONTROL if control is None else control
    return (
        law_findings(used, table)
        + table_findings(used, table, known)
        + dependency_findings(used, table)
        + control_findings(control, table)
    )


def coordinate_problems() -> list[str]:
    """The three path shapes a coordinate is read from."""
    cases = {
        "examples/ch01-getting-started/02-checking.metta": (1, 0, 2),
        "examples/ch07-control-flow/07-05-recursion/06-peano.metta": (7, 5, 6),
        "examples/ch01-getting-started/_fixtures/01-reaches-forward.metta": (1, 0, 1),
    }
    return [
        f"coordinate({path}) is {coordinate(path)}, expected {expected}"
        for path, expected in cases.items()
        if coordinate(path) != expected
    ]


def hash_row_problems() -> list[str]:
    """A `#`-prefixed construct survives a write-then-read round trip."""
    used = {"examples/ch05-equations-and-evaluation/05-04-back/01-r.metta": {"#*"}}
    table = read_table(write_table(used))
    if table.get("#*") == (5, 4, 1):
        return []
    return [f"#* was lost in the table round trip; read back as {table.get('#*')!r}"]


def plant_problems() -> list[str]:
    """Each planted violation must produce a finding, and the fixture none."""
    problems = []
    if all_findings():
        problems.append(f"the consistent fixture is not clean: {all_findings()}")

    # Each plant names the words its OWN rule must say. A plant that merely
    # produces "a finding" proves nothing: half of these disturb the fixture
    # enough that a second rule would fire too, and a gate that catches the
    # wrong thing for the right input is the failure this file exists to stop.
    plants = {
        "a forward reference": (
            {"used": {**USED, "examples/ch01-getting-started/03-early.metta": {"if"}}},
            "is 01-00-03 and uses if, introduced at 07-01-01",
        ),
        "a construct with no row": (
            {"used": {**USED, "examples/ch01-getting-started/03-new.metta": {"nop"}}},
            "uses nop, which has no row",
        ),
        "a file that does not parse": (
            {
                "used": {
                    **USED,
                    "examples/ch01-getting-started/03-broken.metta": {"?PARSE-ERROR"},
                }
            },
            "does not parse, so nothing was checked",
        ),
        "a row no example uses": (
            {"table": {**TABLE, "hyperpose": (9, 0, 1)}},
            "hyperpose has a row but no example uses it",
        ),
        "a row placed before its earliest use": (
            {"table": {**TABLE, "if": (1, 0, 1)}},
            "if is introduced at 07-01-01 but its row says 01-00-01",
        ),
        "a row naming a non-construct": (
            {
                "table": {**TABLE, "the-answer": (1, 0, 1)},
                "used": {
                    **USED,
                    "examples/ch01-getting-started/03-own.metta": {"the-answer"},
                },
            },
            "the-answer has a row but is not a construct the engine publishes",
        ),
        # `if` never appears without `test`, so `test` may not be introduced
        # later than `if`. The law alone does not see this: every USE of both
        # still follows both rows, which is why the floor is a rule of its own.
        "a dependency inversion": (
            {
                "table": {**TABLE, "test": (9, 0, 1), "if": (8, 0, 1)},
                "used": {
                    **USED,
                    "examples/ch09-types/01-t.metta": {"test"},
                    "examples/ch08-data/01-d.metta": {"if", "test", "+", "!"},
                },
            },
            "if never appears without test",
        ),
        "a negative control the law no longer catches": (
            {
                "table": {**TABLE, "if": (1, 0, 1)},
                "used": {
                    **USED,
                    "examples/ch01-getting-started/03-early.metta": {"if"},
                },
            },
            "the lane is not checking anything",
        ),
    }
    for name, (keywords, expected) in plants.items():
        found = all_findings(**keywords)
        if not any(expected in finding for finding in found):
            problems.append(
                f"planted {name} produced no finding saying {expected!r}; got {found}"
            )
    return problems


def main() -> int:
    """Print every way the gate failed to notice a planted violation."""
    problems = plant_problems() + coordinate_problems() + hash_row_problems()
    for problem in problems:
        print(problem)
    print(
        f"cumulative-syntax selftest: {len(problems)} problem(s) across "
        f"8 plants, 3 coordinate shapes and 1 table round trip"
    )
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
