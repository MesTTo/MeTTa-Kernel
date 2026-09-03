"""Purpose: prove the llms lane can fail, one planted fault per check.

A green lane is worth what its red is worth. The llms lane exists because a
cheat sheet claimed a gate that did not exist and drifted for three days
behind the claim, so this file plants exactly the drift each half is supposed
to catch and fails when the checker reports it green.

The checker's five parts are pure functions over (sheet, text), so each
fault is planted in TEXT rather than by writing a broken llms.txt into the
tree: a selftest that edited the shipped sheet would race the lane reading it.
The engine half takes its vocabulary as an argument for the same reason, and
so runs here without swipl.

Assumes: it runs from a checkout of this repository.
Guarantees:
  - a path claim naming nothing, a roster omitting a shipped library, a roster
    naming an absent one, a count disagreeing with lib/, and a language-surface
    name the engine does not know are each caught, and a clean text of the same
    shape reports nothing [tested: this file is its own test, run by the gate;
    commit=b089d4309f34b205c5fdaee46960d1fcd9c1ac42]
  - Python methods are checked on the class named by their receiver, including
    calls in compact unlabelled API blocks [tested: this file is its own test,
    run by the gate; commit=b089d4309f34b205c5fdaee46960d1fcd9c1ac42]
  - the real sheets are read by the lane itself, never edited here, so a
    planted fault cannot race the lane reading the shipped file [tested:
    tests/checks/check_llms_names.py; commit=b089d4309f34b205c5fdaee46960d1fcd9c1ac42]
  - a wrong source-table count and an omitted corpus-used engine head each
    turn their production checker red independently [tested: this file is its
    own test, run by the gate; commit=WORKTREE]
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from check_llms_names import (  # noqa: E402  -- HERE must be on the path first
    REPO,
    count_findings,
    head_findings,
    library_findings,
    method_findings,
    omitted_head_findings,
    path_findings,
)

SHEET = REPO / "llms.txt"
PYTHON_SHEET = REPO / "extensions/python/llms.txt"


def _shipped() -> list[str]:
    return sorted(path.name for path in (REPO / "lib").glob("lib_*") if path.is_dir())


def _roster(names: list[str], count: int | None = None) -> str:
    listed = ", ".join(f"`{name}`" for name in names)
    total = len(names) if count is None else count
    return f"{total} libraries load with `!(import! ...)`: {listed}. Scored answers"


def _surface(body: str) -> str:
    return f"## The MeTTa language surface\n\nblah\n\n```\n{body}\n```\n"


def main() -> int:
    """Plant one fault per check and require each to be caught."""
    failures: list[str] = []

    def expect(condition: bool, message: str) -> None:
        if not condition:
            failures.append(message)

    # PATHS: a claim that resolves, and one that does not.
    expect(
        path_findings(SHEET, "see `engine/ext_points.pl` for the seams") == [],
        "a resolving path claim was reported",
    )
    expect(
        len(path_findings(SHEET, "see `engine/no_such_unit.pl` for the seams")) == 1,
        "a path claim naming nothing was NOT reported",
    )
    expect(
        path_findings(SHEET, "`add-atom/3` and `metta.run/match/eval`") == [],
        "a predicate indicator or door list was read as a path",
    )

    # LIBRARIES: the roster and both statements of its count.
    shipped = _shipped()
    expect(
        library_findings(SHEET, _roster(shipped)) == [],
        "an exact roster was reported",
    )
    expect(
        any(
            "omits" in finding
            for finding in library_findings(SHEET, _roster(shipped[:-1], len(shipped)))
        ),
        "a roster omitting a shipped library was NOT reported",
    )
    expect(
        any(
            "does not ship" in finding
            for finding in library_findings(
                SHEET, _roster([*shipped, "lib_invented"], len(shipped))
            )
        ),
        "a roster naming an absent library was NOT reported",
    )
    expect(
        any(
            "libraries, lib/ ships" in finding
            for finding in library_findings(SHEET, _roster(shipped, len(shipped) - 1))
        ),
        "a roster count disagreeing with lib/ was NOT reported",
    )
    table = f"| `lib/lib_*/lib_*.metta` | {len(shipped) - 1} MeTTa libraries loaded with x |"
    expect(
        any("sources table says" in finding for finding in library_findings(SHEET, table)),
        "a sources-table count disagreeing with lib/ was NOT reported",
    )

    expect(
        any(
            "roster is gone" in finding
            for finding in library_findings(SHEET, "a sheet with no roster at all")
        ),
        "a root sheet whose roster vanished was NOT reported",
    )
    expect(
        library_findings(REPO / "extensions/python/llms.txt", "a seat sheet") == [],
        "a seat sheet without a roster was reported",
    )

    # COUNTS: use the real table as the clean control, then corrupt one claim
    # in memory. The production derivation still reads the named source.
    source_text = SHEET.read_text(encoding="utf-8")
    expect(
        count_findings(SHEET, source_text) == [],
        "the sources table's exact counts were reported",
    )
    count = re.search(r"(?P<count>\d+) executable programs", source_text)
    expect(count is not None, "the planted count target vanished from llms.txt")
    if count is not None:
        wrong_count = str(int(count.group("count")) + 1)
        planted = (
            source_text[: count.start("count")] + wrong_count + source_text[count.end("count") :]
        )
        expect(
            any(
                "executable example programs" in finding
                for finding in count_findings(SHEET, planted)
            ),
            "a wrong source-table count was NOT reported",
        )

    # The engine half must not fail OPEN: a swipl that ran and failed is a
    # finding, where a swipl that is not installed is a skip.
    import check_llms_names as lane  # noqa: PLC0415  -- patched for one case

    original = lane.subprocess.run
    try:
        lane.subprocess.run = lambda *a, **k: type(  # noqa: ARG005
            "Result", (), {"returncode": 1, "stdout": "", "stderr": "boom"}
        )()
        broke = False
        try:
            lane.engine_vocabulary()
        except RuntimeError:
            broke = True
        except lane.EngineUnavailable:
            broke = False
        expect(broke, "an engine that RAN and failed was treated as absent")
    finally:
        lane.subprocess.run = original

    # HEADS: the surface block against a vocabulary the engine supplies.
    known = {"if", "case", "let"}
    expect(
        head_findings(SHEET, _surface("if case let"), known) == [],
        "a surface block of known heads was reported",
    )
    expect(
        len(head_findings(SHEET, _surface("if case let not-a-head"), known)) == 1,
        "a surface name the engine does not know was NOT reported",
    )

    expect(
        any(
            "language-surface block is gone" in finding
            for finding in head_findings(SHEET, "a sheet with no surface block", known)
        ),
        "a root sheet whose surface block vanished was NOT reported",
    )
    expect(
        head_findings(REPO / "extensions/python/llms.txt", "a seat sheet", known) == [],
        "a seat sheet without a surface block was reported",
    )

    # USED HEADS: the reverse direction. An exact token mention covers a live,
    # corpus-used head; a longer neighbouring symbol does not.
    uses = {"println!": 76, "get-atoms": 15}
    used_known = set(uses)
    expect(
        omitted_head_findings(SHEET, "`println!` and `get-atoms`", used_known, uses) == [],
        "documented corpus-used heads were reported",
    )
    omitted = omitted_head_findings(SHEET, "`println!` only", used_known, uses)
    expect(
        len(omitted) == 1 and "`get-atoms`" in omitted[0],
        "an omitted corpus-used engine head was NOT reported",
    )
    expect(
        any(
            "`print`" in finding
            for finding in omitted_head_findings(
                SHEET,
                "`println!` is a different head",
                {"print"},
                {"print": 1},
            )
        ),
        "a longer head name falsely covered an omitted shorter one",
    )

    # METHODS: a code block teaches, while prose can discuss or deny a name.
    block = "```python\nm.query(pattern)\n```"
    expect(
        any("m.query" in finding for finding in method_findings(SHEET, block)),
        "a method the library does not have was NOT reported",
    )
    expect(
        method_findings(SHEET, "```python\nm.match(pattern)\nkb.remove(a)\n```") == [],
        "real methods were reported",
    )
    expect(
        method_findings(SHEET, "prose saying there is no `metta.matching` here") == [],
        "prose DENYING a method was read as teaching it",
    )
    expect(
        method_findings(SHEET, "```ts\nm.dispose()\n```") == [],
        "another language's block was read as this package's methods",
    )
    expect(
        any(
            "m.query" in finding
            for finding in method_findings(PYTHON_SHEET, "```\nm.query(pattern)\n```")
        ),
        "an unlabelled Python API block was NOT inspected",
    )
    expect(
        any(
            "m._register_space" in finding
            for finding in method_findings(
                PYTHON_SHEET,
                "```python\nm._register_space(provider, '&crm')\n```",
            )
        ),
        "a Space-only method written on a MeTTa context was NOT reported",
    )
    expect(
        any(
            "kb.close" in finding
            for finding in method_findings(PYTHON_SHEET, "```python\nkb.close()\n```")
        ),
        "a MeTTa-only method written on a Space was NOT reported",
    )
    expect(
        any(
            "context.answers" in finding
            for finding in method_findings(SHEET, "```python\ncontext.answers(term)\n```")
        ),
        "an invalid method on the named context receiver was NOT reported",
    )
    expect(
        method_findings(
            SHEET,
            "```python\nm.answers(term)\ncontext.close()\n```",
        )
        == [],
        "valid methods were reported on the root sheet's Space and context",
    )
    expect(
        method_findings(
            PYTHON_SHEET,
            "```python\nm.close()\nkb.answers(term)\nkb._register_space(provider, '&crm')\n```",
        )
        == [],
        "valid methods were reported on the Python sheet's context and Space",
    )

    for failure in failures:
        print(failure, file=sys.stderr)
    print(f"llms selftest: 31 planted case(s), {len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
