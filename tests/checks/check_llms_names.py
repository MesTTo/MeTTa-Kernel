"""Purpose: hold every llms.txt to the tree and the engine it describes.

llms.txt opens by promising this: "Names here are checked against the live
engine and the real file tree by `check.sh`'s `llms` lane, so a rename breaks
the build instead of misleading you." That lane did not exist. The promise was
written on 2026-08-29 and nothing behind it ever ran, which is how the library
roster came to name 33 of 34 libraries, omit `lib_dict` and `lib_gitimport`,
and say so in two places for three days without a red lane [measured
2026-09-01, the audit that found it].

A cheat sheet is the one document read by something that cannot notice a stale
claim, so the file that asserts its own gate and has none is worse off than one
admitting it is hand-kept. Three checks, one per half of the promise:

  PATHS       every backticked token that names a file or directory resolves,
              a glob resolving to at least one match. This is the "real file
              tree" half.
  LIBRARIES   the roster sentence's names and its count equal `lib/lib_*/`.
              The count is stated twice, in the sources table and in the
              roster, and both are read.
  HEADS       every name in the language-surface block is one the engine gives
              meaning to, asked of the ENGINE rather than of a list. Both
              questions are asked, `fun/1` and the translator's own
              metta_translated_head/1, because a head has meaning through
              either and asking one alone reports the other's names as unknown.

Assumes:
  - swipl is on PATH; without it the HEADS half is skipped aloud rather than
    silently, the way the sibling lanes skip a missing toolchain.
  - it runs from a checkout of this repository.
Guarantees:
  - a path that stopped resolving, a roster that stopped matching `lib/`, a
    count that stopped matching its own roster, and a language-surface name the
    engine does not know each fail independently and name the file and line
    [tested: tests/checks/check_llms_selftest.py]
  - every llms.txt in the tree is read, the root's and each seat's, so a seat
    sheet is not exempt from the promise the root makes
    [tested: tests/checks/check_llms_selftest.py]
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

#: A backticked token is a PATH claim only when it is unambiguously one: it
#: carries a known file extension, or it ends in a separator. Everything else
#: with a slash in it is a name -- `add-atom/3` is a predicate indicator,
#: `metta.run/match/eval` is a list of doors, `metta-node/spaces` is a module
#: specifier -- and reading those as paths reported nine names as missing
#: files on this lane's first run. A claim resolves against the sheet's OWN
#: directory or the repository root, and a multi-segment one may also name a
#: real path by suffix, which is how a sheet writes `tests/repository/` as
#: `repository/` in prose without lying about the tree.
_SUFFIXES = frozenset(
    {".pl", ".plt", ".py", ".pyi", ".md", ".metta", ".c", ".h", ".ts", ".mjs",
     ".json", ".txt", ".sh", ".so", ".toml", ".yml", ".ipynb", ".rs", ".lean"}
)


#: A path is spelled in path characters. `#//` and its `#`-prefixed kin are
#: the relational-arithmetic operators, and a trailing-slash test alone read
#: the first of them as a directory.
_PATH_CHARACTERS = re.compile(r"^[\w.\-*/]+$")


def _is_path_claim(token: str) -> bool:
    if not _PATH_CHARACTERS.match(token):
        return False
    return token.endswith("/") or Path(token).suffix in _SUFFIXES


def _resolves(sheet: Path, token: str) -> bool:
    """Whether a path claim names something the tree actually holds."""
    bases = (sheet.parent, REPO)
    if "*" in token:
        return any(list(base.glob(token)) for base in bases)
    if any((base / token.lstrip("/")).exists() for base in bases):
        return True
    # A prose shorthand names a real path by its tail: `repository/` for
    # tests/repository/, `gallery/` for the examples one.
    tail = token.strip("/")
    if "/" not in tail:
        # A bare name may be a file the sheet names without its directory,
        # `ext_points.plt` for the suite of that name, as well as a directory.
        return any(
            ".git" not in candidate.parts for candidate in REPO.rglob(tail)
        )
    return any(
        str(candidate.relative_to(REPO)).endswith(tail)
        for candidate in REPO.rglob(Path(tail).name)
        if ".git" not in candidate.parts
    )

#: The roster sentence, whose count and names both have to match `lib/`.
_ROSTER = re.compile(
    r"(?P<count>\d+) libraries load with .*?:(?P<names>.*?)\. Scored",
    re.DOTALL,
)
#: The same count where the sources table states it a second time.
_TABLE_COUNT = re.compile(r"\|\s*`lib/lib_\*/lib_\*\.metta`\s*\|\s*(?P<count>\d+) MeTTa libraries")

#: The receiver names the sheets use in their examples. A door written on one
#: of these has to exist on the library; anything else with a dot is a module
#: path, a file or prose. `m` is a context in one sheet and a space in
#: another, so a door is checked against BOTH tiers and the package: the
#: question worth failing on is "does this door exist at all", and asking it
#: per tier reported forty names that were only written on the other one.
_RECEIVERS = frozenset({"m", "kb", "space", "store", "metta"})
_DOOR = re.compile(r"\b(" + "|".join(sorted(_RECEIVERS)) + r")\.(\w+)")


def _python_blocks(text: str) -> str:
    """The python fenced blocks, every other line blanked.

    Blanked rather than dropped so a finding's line number still points at the
    sheet's own line.
    """
    inside = False
    kept: list[str] = []
    for line in text.splitlines():
        if line.startswith("```"):
            inside = line.strip() == "```python"
            kept.append("")
        else:
            kept.append(line if inside else "")
    return "\n".join(kept)


def door_findings(sheet: Path, text: str) -> list[str]:
    """Every door a sheet teaches that the library does not have.

    `m.query(...)` sat in the Python seat's sheet in three places and had
    never existed on either tier; nothing read the sheet, so nothing said so
    [measured 2026-09-01]. Read from the CLASSES rather than an instance, so
    the check costs an import instead of an engine boot.
    """
    seat = str(REPO / "extensions" / "python")
    if seat not in sys.path:
        sys.path.insert(0, seat)
    try:
        import metta as package  # noqa: PLC0415  -- imported only when the lane runs
    except ImportError as absent:
        # The package is IN THIS TREE, so failing to import it is a finding
        # rather than a skip: returning "nothing to check" would take this
        # half green on exactly the tree where the doors moved.
        return [
            f"{sheet.relative_to(REPO)}: the metta package under "
            f"extensions/python did not import, so no door was checked: {absent}"
        ]
    known = (
        set(dir(package))
        | set(dir(package.MeTTa))
        | set(dir(package.Space))
        | set(dir(package.Atom))
    )
    findings: list[str] = []
    # Only a PYTHON CODE BLOCK teaches a door. Prose discusses one, including
    # to say it does not exist -- the root sheet's "there is no
    # `metta.measure` and no `metta.matching`" is a true sentence this half
    # read as two false claims -- and another seat's blocks are another
    # language's objects, where `m.dispose` is correct TypeScript and nothing
    # to do with this package.
    text = _python_blocks(text)
    for match in _DOOR.finditer(text):
        receiver, door = match.groups()
        whole = f"{receiver}.{door}"
        if Path(whole).suffix in _SUFFIXES or door in known:
            continue
        findings.append(
            f"{sheet.relative_to(REPO)}:{_line_of(text, match.start())}: teaches "
            f"`{whole}`, which the library has on no tier"
        )
    return findings


#: The language-surface block: one fenced run of bare head names.
_SURFACE_BLOCK = re.compile(
    r"## The MeTTa language surface.*?```\n(?P<body>.*?)```",
    re.DOTALL,
)


def sheets() -> list[Path]:
    """Every llms.txt the tree ships, the root's first."""
    root = REPO / "llms.txt"
    seats = sorted((REPO / "extensions").glob("*/llms.txt"))
    return [path for path in (root, *seats) if path.is_file()]


def _line_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def path_findings(sheet: Path, text: str) -> list[str]:
    """Every backticked path claim that no longer resolves."""
    findings: list[str] = []
    for match in re.finditer(r"`([^`\n]+)`", text):
        token = match.group(1).strip()
        if "://" in token or " " in token or not _is_path_claim(token):
            continue
        if not _resolves(sheet, token):
            findings.append(
                f"{sheet.relative_to(REPO)}:{_line_of(text, match.start())}: "
                f"`{token}` names nothing in the tree"
            )
    return findings


def library_findings(sheet: Path, text: str) -> list[str]:
    """The roster's names and both statements of its count, against `lib/`."""
    findings: list[str] = []
    shipped = {path.name for path in sorted((REPO / "lib").glob("lib_*")) if path.is_dir()}
    roster = _ROSTER.search(text)
    if roster is None and sheet == REPO / "llms.txt":
        # Absence is a finding for the sheet that HAS a roster and a skip for
        # the seat sheets that never did. Reading "no match" as "nothing to
        # check" everywhere would let the roster be deleted or reshaped into
        # a green lane, the fail-open shape this file exists to refuse. The
        # count half below still runs either way, because the two claims can
        # go stale independently.
        findings.append(
            f"{sheet.relative_to(REPO)}: the library roster is gone or no "
            f"longer reads as `N libraries load with ...: `lib_x`, ... . Scored`, "
            f"so its {len(shipped)} names go unchecked"
        )
    if roster is not None:
        named = set(re.findall(r"`(lib_\w+)`", roster.group("names")))
        line = _line_of(text, roster.start())
        for missing in sorted(shipped - named):
            findings.append(
                f"{sheet.relative_to(REPO)}:{line}: the roster omits `{missing}`, "
                f"which lib/ ships"
            )
        for absent in sorted(named - shipped):
            findings.append(
                f"{sheet.relative_to(REPO)}:{line}: the roster names `{absent}`, "
                f"which lib/ does not ship"
            )
        stated = int(roster.group("count"))
        if stated != len(shipped):
            findings.append(
                f"{sheet.relative_to(REPO)}:{line}: the roster says {stated} "
                f"libraries, lib/ ships {len(shipped)}"
            )
    for match in _TABLE_COUNT.finditer(text):
        stated = int(match.group("count"))
        if stated != len(shipped):
            findings.append(
                f"{sheet.relative_to(REPO)}:{_line_of(text, match.start())}: the "
                f"sources table says {stated} libraries, lib/ ships {len(shipped)}"
            )
    return findings


class EngineUnavailable(Exception):
    """swipl is not installed, which is a skip; anything else is a finding."""


def engine_vocabulary() -> set[str]:
    """Every head the engine gives meaning to.

    Raises EngineUnavailable only when swipl is not installed at all. An
    engine that RAN and failed is a finding, never a skip: returning the
    absent-toolchain answer for both would let a broken engine take this
    half of the lane quietly green, which is the fail-open shape a gate
    exists to refuse.

    BOTH questions are asked. A head has meaning through `fun/1` or through
    the translator, and asking one alone reports the other's names as unknown:
    of the special forms, `case`, `if`, `collapse`, `quote` and their kin
    answer false to `fun/1` and are still perfectly callable.
    """
    goal = (
        "ensure_loaded('engine/qlf_boot.pl'), ensure_loaded('engine/metta.pl'), "
        "forall(( metta_grounded_token(N) ; fun(N) "
        "; translator:metta_special_form_head(N) ; translator:metta_translated_head(N) ), "
        "( print_message_lines(user_output, '', []), format('~w~n', [N]) ))"
    )
    try:
        finished = subprocess.run(
            ["swipl", "-g", goal, "-t", "halt", "--", "extensions"],
            cwd=REPO,
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError as absent:
        raise EngineUnavailable from absent
    if finished.returncode != 0:
        detail = (finished.stderr or finished.stdout).strip().splitlines()
        tail = detail[-1] if detail else "no output"
        msg = f"the engine did not answer its vocabulary: {tail}"
        raise RuntimeError(msg)
    return {line.strip() for line in finished.stdout.splitlines() if line.strip()}


def head_findings(sheet: Path, text: str, known: set[str]) -> list[str]:
    """Every language-surface name the engine does not answer to."""
    block = _SURFACE_BLOCK.search(text)
    if block is None:
        # The third fail-open of the same shape: a heading renamed or a fence
        # dropped would take this half green. It is a finding for the sheet
        # that HAS the section and a skip for the seats that never did.
        if sheet == REPO / "llms.txt":
            return [
                f"{sheet.relative_to(REPO)}: the language-surface block is gone "
                f"or no longer reads as a fenced run under "
                f"'## The MeTTa language surface', so its names go unchecked"
            ]
        return []
    line = _line_of(text, block.start("body"))
    return [
        f"{sheet.relative_to(REPO)}:{line}: the language-surface block names "
        f"`{name}`, which the engine does not know"
        for name in sorted(set(block.group("body").split()) - known)
    ]


def main(argv: list[str] | None = None) -> int:
    """Report every stale claim, or say what was checked."""
    del argv
    findings: list[str] = []
    known: set[str] | None
    try:
        known = engine_vocabulary()
    except EngineUnavailable:
        known = None
    except RuntimeError as broken:
        known = None
        findings.append(f"llms: {broken}")
    for sheet in sheets():
        text = sheet.read_text(encoding="utf-8")
        findings.extend(path_findings(sheet, text))
        findings.extend(library_findings(sheet, text))
        findings.extend(door_findings(sheet, text))
        if known is not None:
            findings.extend(head_findings(sheet, text, known))
    for finding in findings:
        print(finding, file=sys.stderr)
    if known is not None:
        where = "against the live engine"
    elif findings and findings[-1].startswith("llms: the engine"):
        where = "with the engine refusing to answer, so heads went unread"
    else:
        where = "with swipl absent, so heads went unread"
    print(
        f"llms: {len(sheets())} cheat sheet(s) read {where}, {len(findings)} finding(s)"
    )
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
