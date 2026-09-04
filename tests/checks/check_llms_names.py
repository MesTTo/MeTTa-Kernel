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
admitting it is hand-kept. Six checks cover both directions of each promise:

  PATHS       every backticked token that names a file or directory resolves,
              a glob resolving to at least one match. This is the "real file
              tree" half.
  LIBRARIES   the roster sentence's names and its count equal `lib/lib_*/`.
              The count is stated twice, in the sources table and in the
              roster, and both are read.
  COUNTS      every explicit source-table count is derived from the path or
              source it describes.
  HEADS       every name in the language-surface block is one the engine gives
              meaning to, asked of the ENGINE rather than of a list. Both
              questions are asked, `fun/1` and the translator's own
              metta_translated_head/1, because a head has meaning through
              either and asking one alone reports the other's names as unknown.
  USED HEADS  every engine-known call head exercised by the example corpus is
              named somewhere in the root cheat sheet. This is the reverse
              question HEADS did not ask.
  RETURNS     every documented `-> Type` agrees with the live return
              annotation, compared by HEAD name so a sheet may be more precise
              than the signature is. A method the annotation says nothing about
              is skipped rather than guessed at.

Assumes:
  - swipl is on PATH; without it the HEADS half is skipped aloud rather than
    silently, the way the sibling lanes skip a missing toolchain.
  - it runs from a checkout of this repository.
Guarantees:
  - a path that stopped resolving, a roster that stopped matching `lib/`, a
    count that stopped matching its own roster, and a language-surface name the
    engine does not know each fail independently and name the file and line
    [tested: tests/checks/check_llms_selftest.py; commit=b089d4309f34b205c5fdaee46960d1fcd9c1ac42]
  - every llms.txt in the tree is read, including the root and each extension,
    so an extension sheet is not exempt from the promise the root makes
    [tested: tests/checks/check_llms_selftest.py; commit=b089d4309f34b205c5fdaee46960d1fcd9c1ac42]
  - each Python call is checked against the receiver's actual class, and an
    unlabelled API block containing such calls is still inspected
    [tested: tests/checks/check_llms_selftest.py; commit=b089d4309f34b205c5fdaee46960d1fcd9c1ac42]
  - source-table counts and reverse corpus-head coverage are derived from the
    files and live vocabulary, with independently planted omissions
    [tested: tests/checks/check_llms_selftest.py; commit=2c376be0bca6f85920288863ac89f09a44e6c0c7]
  - the library count is attached to the shipped directories rather than a
    `.metta`-only glob that omits a Prolog-only implementation [tested:
    tests/checks/check_llms_selftest.py;
    commit=1bfad3db85807fff774cad370ff8e57f7400ae99]
  - a documented return type the live annotation contradicts is reported, while
    a prose tail, a module qualifier, an omitted parameter, a positional tuple
    and a sheet more precise than the signature are not [tested:
    tests/checks/check_llms_selftest.py; commit=4ef96c94579db405fafed8fdaab20e33901a2298]
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None.
"""

from __future__ import annotations

import inspect
import re
import subprocess
import sys
from collections.abc import Mapping
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
    {
        ".pl",
        ".plt",
        ".py",
        ".pyi",
        ".md",
        ".metta",
        ".c",
        ".h",
        ".ts",
        ".mjs",
        ".json",
        ".txt",
        ".sh",
        ".so",
        ".toml",
        ".yml",
        ".ipynb",
        ".rs",
        ".lean",
    }
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
        return any(".git" not in candidate.parts for candidate in REPO.rglob(tail))
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
_TABLE_COUNT = re.compile(r"\|\s*`lib/lib_\*/`\s*\|\s*(?P<count>\d+) MeTTa libraries")

#: Each count is anchored to the table row that makes the claim. A missing
#: match is itself a finding, so deleting the number cannot disable its check.
#: Word forms are included because the prose uses them for several small
#: counts; treating only decimal digits as claims was the original blind spot.
_COUNT_CLAIMS = (
    (
        "executable example programs",
        re.compile(r"\| `examples/\*\*/\*\.metta` \| (?P<count>\d+) executable programs"),
        "example_programs",
    ),
    (
        "example chapters",
        re.compile(
            r"\| `examples/\*\*/\*\.metta` \|[^\n]*? in (?P<count>\d+) "
            r"(?:numbered )?chapters"
        ),
        "example_chapters",
    ),
    (
        "highest example chapter number",
        re.compile(r"\| `examples/\*\*/\*\.metta` \|[^\n]*? numbered to (?P<count>\d+)"),
        "highest_example_chapter",
    ),
    (
        "skipped examples",
        re.compile(
            r"\| `examples/\*\*/\*\.metta` \|[^\n]*? names the (?P<count>[a-z]+|\d+) that do not"
        ),
        "skipped_examples",
    ),
    (
        "generated reference pages",
        re.compile(r"\| `website/reference/metta-\*\.md` \| (?P<count>\d+) pages"),
        "reference_pages",
    ),
    (
        "Python test chapters",
        re.compile(
            r"\| `extensions/python/tests/\*/test_\*\.py` \|[^\n]*? same (?P<count>\d+) chapters"
        ),
        "python_test_chapters",
    ),
    (
        "guide pages",
        re.compile(r"\| `website/guide/\*\.md` \| (?P<count>\d+) pages"),
        "guide_pages",
    ),
    (
        "tutorial pages",
        re.compile(r"\| `website/tutorials/\*\.md` \| (?P<count>\d+) numbered lessons"),
        "tutorial_pages",
    ),
    (
        "gallery programs",
        re.compile(
            r"\| `extensions/python/examples/\*/\*\.py` \|[^\n]*? the (?P<count>[a-z]+|\d+) under `gallery/`"
        ),
        "gallery_programs",
    ),
    (
        "engine metta units",
        re.compile(
            r"\| `engine/\*\*/\*\.pl` \|[^\n]*? the "
            r"(?P<count>[a-z]+|\d+) `engine/metta/\*\.pl` units"
        ),
        "metta_units",
    ),
    (
        "engine translator units",
        re.compile(
            r"\| `engine/\*\*/\*\.pl` \|[^\n]*? the "
            r"(?P<count>[a-z]+|\d+) `engine/translator/\*\.pl` units"
        ),
        "translator_units",
    ),
    (
        "engine spaces units",
        re.compile(
            r"\| `engine/\*\*/\*\.pl` \|[^\n]*? the "
            r"(?P<count>[a-z]+|\d+) `engine/spaces/\*\.pl` units"
        ),
        "spaces_units",
    ),
    (
        "reader.c lines",
        re.compile(
            r"\| `engine/\*\*/\*\.pl` \|[^\n]*?`engine/reader\.c`, "
            r"(?P<count>[\d,]+) lines"
        ),
        "reader_lines",
    ),
    (
        "json_codec.c lines",
        re.compile(
            r"\| `engine/\*\*/\*\.pl` \|[^\n]*?`engine/json_codec\.c`, "
            r"(?P<count>[\d,]+) lines"
        ),
        "json_codec_lines",
    ),
    (
        "extension-point kinds",
        re.compile(
            r"\| `engine/ext_points\.pl` \|[^\n]*? (?P<count>[A-Za-z]+|\d+) "
            r"of them, and the count of each"
        ),
        "extension_point_kinds",
    ),
    *(
        (
            f"{kind} extension points",
            re.compile(
                rf"\| `engine/ext_points\.pl` \|[^\n]*?`{kind}` "
                rf"(?P<count>\d+)"
            ),
            f"extension_points_{kind}",
        )
        for kind in ("host_service", "service", "ownership", "event", "declaration")
    ),
)

_NUMBER_WORDS = {
    "zero": 0,
    "one": 1,
    "two": 2,
    "three": 3,
    "four": 4,
    "five": 5,
    "six": 6,
    "seven": 7,
    "eight": 8,
    "nine": 9,
    "ten": 10,
}

#: Receiver names used by the Python examples. The same spelling can denote a
#: different class in each sheet, so the class is selected before a method is
#: checked. ``self`` is the one supported property hop because the Python
#: extension sheet teaches context.self methods directly.
_RECEIVERS = frozenset({"m", "context", "ctx", "kb", "space", "store", "metta"})
_METHOD = re.compile(
    r"\b(?P<receiver>" + "|".join(sorted(_RECEIVERS)) + r")\.(?:(?P<via>self)\.)?(?P<method>\w+)"
)
_ROOT_SHEET = REPO / "llms.txt"
_PYTHON_SHEET = REPO / "extensions/python/llms.txt"
_PYTHON_DOCUMENTS = frozenset({_ROOT_SHEET, _PYTHON_SHEET})


def _python_blocks(sheet: Path, text: str) -> str:
    """Return Python examples with every other source line blanked.

    Explicit ``python`` fences always qualify. In the two Python documents, an
    unlabelled fence qualifies when it contains a recognized receiver call.
    That admits compact signature tables while leaving MeTTa source blocks
    alone. Blanking preserves each finding's source line.
    """
    lines = text.splitlines()
    kept = [""] * len(lines)
    inside = False
    language = ""
    body_start = 0

    def retain(body_end: int) -> None:
        body = lines[body_start:body_end]
        inferred = (
            language == ""
            and sheet in _PYTHON_DOCUMENTS
            and any(_METHOD.search(line) for line in body)
        )
        if language == "python" or inferred:
            kept[body_start:body_end] = body

    for index, line in enumerate(lines):
        if not line.startswith("```"):
            continue
        if not inside:
            inside = True
            language = line.removeprefix("```").strip()
            body_start = index + 1
            continue
        retain(index)
        inside = False
        language = ""
    if inside:
        retain(len(lines))
    return "\n".join(kept)


def _receivers(sheet: Path) -> tuple[dict[str, tuple[object, str]], list[str]]:
    """The documented receiver names bound to the live classes they stand for.

    The second element carries the import failure and is empty when the
    package loaded. The bindings read classes rather than instances, so they
    cost one import and never boot an engine. The root sheet binds ``m`` to
    ``Space``; the Python extension sheet binds it to ``MeTTa``. Named spaces
    always use ``Space``.
    """
    python_path = str(REPO / "extensions" / "python")
    if python_path not in sys.path:
        sys.path.insert(0, python_path)
    try:
        import metta as package  # noqa: PLC0415  -- imported only when the lane runs
    except ImportError as absent:
        # The package is IN THIS TREE, so failing to import it is a finding
        # rather than a skip: returning "nothing to check" would take this
        # half green on exactly the tree where the doors moved.
        return {}, [
            f"{sheet.relative_to(REPO)}: the metta package under "
            f"extensions/python did not import, so no method was checked: {absent}"
        ]

    m_class = package.Space if sheet == _ROOT_SHEET else package.MeTTa
    return {
        "m": (m_class, m_class.__name__),
        "context": (package.MeTTa, "MeTTa"),
        "ctx": (package.MeTTa, "MeTTa"),
        "kb": (package.Space, "Space"),
        "space": (package.Space, "Space"),
        "store": (package.Space, "Space"),
        "metta": (package, "the metta package"),
    }, []


def method_findings(sheet: Path, text: str) -> list[str]:
    """Every taught Python method absent from its documented receiver."""
    receivers, failure = _receivers(sheet)
    if failure:
        return failure
    findings: list[str] = []
    # Only Python blocks teach Python calls. Prose can deny that a name exists,
    # and another language can correctly expose a different method set.
    code = _python_blocks(sheet, text)
    for match in _METHOD.finditer(code):
        receiver = match.group("receiver")
        via = match.group("via")
        method = match.group("method")
        target, label = receivers[receiver]
        whole = match.group(0)
        if via is not None:
            if via not in dir(target):
                findings.append(
                    f"{sheet.relative_to(REPO)}:{_line_of(code, match.start())}: "
                    f"teaches `{whole}`, but {label} has no `{via}` property"
                )
                continue
            target, label = receivers["kb"]
        if method in dir(target):
            continue
        findings.append(
            f"{sheet.relative_to(REPO)}:{_line_of(code, match.start())}: teaches "
            f"`{whole}`, but {label} has no `{method}` method"
        )
    return findings


#: A DOCUMENTED SIGNATURE: a receiver call carrying a return annotation. The
#: `->` is what makes this safe to read as a declaration. A signature line has
#: one and a call example never does, which keeps the check off the twenty-odd
#: `kw=value` lines in these sheets that PASS a value rather than state a
#: default.
#:
#: Checking those defaults was tried and abandoned. `m.trace`'s live default is
#: None, with the real 10,000 bound resolved in the body, so it is textually
#: identical to `m.limits(inferences=10_000)` passing a value: no rule
#: separates the one stale line from five correct ones [measured 2026-09-04,
#: 28 documented keyword arguments across the five sheets, 23 of them
#: call-example values]. pydoclint reaches the same split, checking return
#: types as DOC203 while documenting that it will not read argument defaults
#: [source: https://jsh9.github.io/pydoclint/violation_codes.html].
_RETURN = re.compile(
    r"\b(?P<receiver>" + "|".join(sorted(_RECEIVERS)) + r")\.(?:(?P<via>self)\.)?"
    r"(?P<method>\w+)\((?P<args>[^()]*(?:\([^()]*\)[^()]*)*)\)\s*->\s*(?P<returns>[^\n#]+)"
)


def _head_type(written: str) -> str:
    """The head name of a written type expression, prose tail removed.

    Both sides of the comparison are TEXT. `from __future__ import annotations`
    leaves a live annotation as its source string rather than an object, which
    is why nothing here evaluates one.

    The head is compared instead of the whole string because these sheets
    decorate a type four ways that are not disagreements: prose after it
    (`int   (atomic, fsynced)`), a module qualifier (`_ops_module.EffectPlan`),
    a parameter the sheet omits (`Answers` for a live `Answers[Any]`), and a
    positional tuple (`(groups, EngineProfile)` for `tuple[...]`). Comparing
    whole strings reported all four. The head survives them and is the part
    carrying the promise: `list` where the live type is `Trace` tells a reader
    the result is an ordinary list, which is the claim that hid
    `Trace.truncated` through two releases.
    """
    text = written.strip()
    depth = 0
    for index, character in enumerate(text):
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth -= 1
        elif depth == 0 and (character in ",;" or text[index : index + 2] == "  "):
            text = text[:index]
            break
    text = text.strip()
    if text.startswith("("):
        return "tuple"
    head = re.match(r"[A-Za-z_][\w.]*", text)
    # A module qualifier says where the type lives, not which type it is.
    return text if head is None else head.group(0).rsplit(".", 1)[-1]


def return_findings(sheet: Path, text: str) -> list[str]:
    """Every documented return type the live annotation contradicts.

    A live signature that says nothing is skipped rather than guessed at: an
    unannotated method and a bare `Any` have no claim to disagree with. A sheet
    is also allowed to be MORE precise than the annotation, so `list[Derivation]`
    against a live `list[Any]` agree on `list`, which is all this asks.
    """
    receivers, failure = _receivers(sheet)
    if failure:
        # method_findings reports the import failure; saying it twice per sheet
        # would only make one fact look like two.
        return []
    findings: list[str] = []
    code = _python_blocks(sheet, text)
    for match in _RETURN.finditer(code):
        target, label = receivers[match.group("receiver")]
        if match.group("via") is not None:
            target, label = receivers["kb"]
        name = match.group("method")
        door = getattr(target, name, None)
        if door is None:
            continue  # method_findings owns the name half of this promise.
        try:
            live = inspect.signature(door).return_annotation
        except (TypeError, ValueError):
            continue
        if live is inspect.Signature.empty:
            continue
        live_head = _head_type(
            live if isinstance(live, str) else getattr(live, "__name__", str(live))
        )
        if live_head in {"Any", "object"}:
            continue
        documented = _head_type(match.group("returns"))
        if documented == live_head:
            continue
        findings.append(
            f"{sheet.relative_to(REPO)}:{_line_of(code, match.start())}: teaches "
            f"`{match.group('receiver')}.{name}(...) -> {documented}`, but "
            f"{label}.{name} answers {live_head}"
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
    extensions = sorted((REPO / "extensions").glob("*/llms.txt"))
    return [path for path in (root, *extensions) if path.is_file()]


def _line_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def _line_count(path: Path) -> int:
    with path.open(encoding="utf-8") as source:
        return sum(1 for _line in source)


def source_counts(root: Path = REPO) -> dict[str, int]:
    """Derive every explicit count in the root sheet's sources table."""
    chapters = sorted(path for path in (root / "examples").glob("ch[0-9][0-9]-*") if path.is_dir())
    examples = [
        path
        for path in (root / "examples").rglob("*.metta")
        if not path.is_symlink() and "_fixtures" not in path.parts
    ]
    skipped = [
        line
        for line in (root / "tests/data/example_skips.txt").read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    test_chapters = [
        path for path in (root / "extensions/python/tests").glob("ch[0-9][0-9]_*") if path.is_dir()
    ]
    # `kind/2` is the source of truth and its few out-of-module clauses are
    # written as `seam:kind/2`. Anchoring to clause heads excludes prose and
    # tests while still following a seam moved to another engine unit.
    extension_kinds: dict[str, int] = {}
    kind_clause = re.compile(r"^(?:seam:)?kind\([^,\n]+,\s*(?P<kind>[a-z_]+)\)\.", re.MULTILINE)
    for path in (root / "engine").rglob("*.pl"):
        for match in kind_clause.finditer(path.read_text(encoding="utf-8")):
            kind = match.group("kind")
            extension_kinds[kind] = extension_kinds.get(kind, 0) + 1
    counts = {
        "example_programs": len(examples),
        "example_chapters": len(chapters),
        "highest_example_chapter": max(int(path.name[2:4]) for path in chapters),
        "skipped_examples": len(skipped),
        "reference_pages": len(list((root / "website/reference").glob("metta-*.md"))),
        "python_test_chapters": len(test_chapters),
        "guide_pages": len(list((root / "website/guide").glob("*.md"))),
        "tutorial_pages": len(list((root / "website/tutorials").glob("*.md"))),
        "gallery_programs": len(list((root / "extensions/python/examples/gallery").glob("*.py"))),
        "metta_units": len(list((root / "engine/metta").glob("*.pl"))),
        "translator_units": len(list((root / "engine/translator").glob("*.pl"))),
        "spaces_units": len(list((root / "engine/spaces").glob("*.pl"))),
        "reader_lines": _line_count(root / "engine/reader.c"),
        "json_codec_lines": _line_count(root / "engine/json_codec.c"),
        "extension_point_kinds": len(extension_kinds),
    }
    counts.update({f"extension_points_{kind}": count for kind, count in extension_kinds.items()})
    return counts


def _number(written: str) -> int:
    normalized = written.replace(",", "").lower()
    if normalized.isdecimal():
        return int(normalized)
    return _NUMBER_WORDS[normalized]


def count_findings(
    sheet: Path,
    text: str,
    counts: Mapping[str, int] | None = None,
) -> list[str]:
    """Every source-table count against the source named by its row."""
    if sheet != _ROOT_SHEET:
        return []
    expected = source_counts() if counts is None else counts
    findings: list[str] = []
    for label, pattern, key in _COUNT_CLAIMS:
        match = pattern.search(text)
        if match is None:
            findings.append(
                f"{sheet.relative_to(REPO)}: the sources table no longer states "
                f"its {label} count, so that count goes unchecked"
            )
            continue
        stated = _number(match.group("count"))
        observed = expected[key]
        if stated != observed:
            findings.append(
                f"{sheet.relative_to(REPO)}:{_line_of(text, match.start())}: "
                f"the sources table says {stated} {label}, the tree has {observed}"
            )
    return findings


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
                f"{sheet.relative_to(REPO)}:{line}: the roster omits `{missing}`, which lib/ ships"
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


def _query_vocabulary(disjunction: str) -> set[str]:
    """Ask one engine process for the distinct names a goal enumerates."""
    goal = (
        "ensure_loaded('engine/qlf_boot.pl'), ensure_loaded('engine/metta.pl'), "
        f"forall(({disjunction}), "
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


def engine_vocabulary() -> set[str]:
    """Every head the forward documentation check accepts.

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
    return _query_vocabulary(
        "metta_grounded_token(N) ; fun(N) "
        "; translator:metta_special_form_head(N) "
        "; translator:metta_translated_head(N)"
    )


def engine_corpus_vocabulary() -> set[str]:
    """The callable set used by the corpus-coverage audit.

    This is deliberately the ledger's measured question: `fun/1` plus
    `metta_translated_head/1`. Special forms are already enumerated by the
    forward language-surface block, while the reverse check guards ordinary
    engine heads that the corpus proves are live.
    """
    return _query_vocabulary("fun(N) ; translator:metta_translated_head(N)")


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


#: This deliberately matches the audit that produced the 64-name repair. It
#: asks only about written call heads, not data and declaration positions, and
#: removes full-line comments before scanning. The live engine intersection
#: below separates callable vocabulary from user-defined heads.
_CALL_HEAD = re.compile(r"\(([a-zA-Z][a-zA-Z0-9_?!*<>=/+\-]*)[\s)]")
_HEAD_CHARACTER = r"a-zA-Z0-9_?!*<>=/+#.\-:"


def corpus_head_uses(root: Path = REPO) -> dict[str, int]:
    """Count written call heads in every shipped MeTTa example."""
    used: dict[str, int] = {}
    for path in sorted((root / "examples").rglob("*.metta")):
        if path.is_symlink() or "_fixtures" in path.parts:
            continue
        body = "\n".join(
            line
            for line in path.read_text(encoding="utf-8").splitlines()
            if not line.lstrip().startswith(";")
        )
        for match in _CALL_HEAD.finditer(body):
            name = match.group(1)
            used[name] = used.get(name, 0) + 1
    return used


def _mentions_head(text: str, name: str) -> bool:
    return (
        re.search(
            rf"(?<![{_HEAD_CHARACTER}]){re.escape(name)}(?![{_HEAD_CHARACTER}])",
            text,
        )
        is not None
    )


def omitted_head_findings(
    sheet: Path,
    text: str,
    known: set[str],
    used: Mapping[str, int] | None = None,
) -> list[str]:
    """Every corpus-used engine head that the root sheet fails to name."""
    if sheet != _ROOT_SHEET:
        return []
    calls = corpus_head_uses() if used is None else used
    return [
        f"{sheet.relative_to(REPO)}: the corpus calls engine head `{name}` "
        f"{calls[name]} time(s), but the sheet never names it"
        for name in sorted(set(calls) & known)
        if not _mentions_head(text, name)
    ]


def main(argv: list[str] | None = None) -> int:
    """Report every stale claim, or say what was checked."""
    del argv
    findings: list[str] = []
    known: set[str] | None
    corpus_known: set[str] | None
    try:
        known = engine_vocabulary()
        corpus_known = engine_corpus_vocabulary()
    except EngineUnavailable:
        known = None
        corpus_known = None
    except RuntimeError as broken:
        known = None
        corpus_known = None
        findings.append(f"llms: {broken}")
    used = corpus_head_uses() if known is not None else {}
    for sheet in sheets():
        text = sheet.read_text(encoding="utf-8")
        findings.extend(path_findings(sheet, text))
        findings.extend(library_findings(sheet, text))
        findings.extend(count_findings(sheet, text))
        findings.extend(method_findings(sheet, text))
        findings.extend(return_findings(sheet, text))
        if known is not None:
            assert corpus_known is not None
            findings.extend(head_findings(sheet, text, known))
            findings.extend(omitted_head_findings(sheet, text, corpus_known, used))
    for finding in findings:
        print(finding, file=sys.stderr)
    if known is not None:
        assert corpus_known is not None
        used_known = set(used) & corpus_known
        root_text = _ROOT_SHEET.read_text(encoding="utf-8")
        covered = sum(1 for name in used_known if _mentions_head(root_text, name))
        where = (
            f"against {len(known)} live engine names; {len(used_known)} of "
            f"{len(corpus_known)} callable names are corpus-used and {covered} "
            "are covered"
        )
    elif findings and findings[-1].startswith("llms: the engine"):
        where = "with the engine refusing to answer, so heads went unread"
    else:
        where = "with swipl absent, so heads went unread"
    print(f"llms: {len(sheets())} cheat sheet(s) read {where}, {len(findings)} finding(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
