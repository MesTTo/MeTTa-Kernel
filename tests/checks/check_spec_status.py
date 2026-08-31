"""Purpose: derive FIXED / OPEN / UNKNOWN for every P<phase>.<n> item in
ai-spec-execution.md by asking the tree, not by reading ai-review-log.md's
prose. P9.3's whole point: the spec's item tables carry an id, an item, an
evidence column and an acceptance criterion, and NO status column; completion
is recorded separately, in prose, in ai-review-log.md. The two documents can
disagree and nothing notices: three already-landed items (P0.4, P0.5, P0.6)
were each dispatched to a fresh agent for exactly this reason [source:
ai-review-log.md, "Integrator error found by two agents in a row, 2026-08-18"].

A verdict needs a checkable ANCHOR: a file path, a `name/arity` Prolog
predicate indicator, a check.sh lane name, or a bare identifier, extracted
from backticked spans in an item's own "item" and "acceptance"-shaped
columns only. The "evidence" column is read but never mined for anchors: it
documents the CURRENT, usually still-true, broken state (a file:line where
the bug lives, the predicate that misbehaves today), and a citation there
being present in the tree proves nothing about whether the fix landed, only
that the bug was real. An item whose acceptance criterion is prose with no
such anchor is UNKNOWN, not guessed: a tool that guesses is worse than no
tool, per this task's own brief.

This module went through three rounds of "run it against the real 158-item
spec, read every FIXED/OPEN line, and ask whether it is actually true," per
this project's own "test, do not predict" rule, and each round found a
confident but WRONG verdict, never a merely-missed one:

  1. A cited `name/arity` or bare identifier existing was first read as a
     FIXED-leaning signal. Wrong for `swrite/2`, `fun/1`, `register_op` and
     most other names this spec cites, because they are the ENGINE'S
     EXISTING API and the item is about changing their BEHAVIOUR, not
     creating them, so they exist identically before and after any fix.
     Worse for a RENAME item (P10.5): finding `m.space_name`, the name
     being RETIRED, still defined is what "not yet renamed" looks like, not
     evidence of progress. Fixed by making PREDICATE and the generic half
     of IDENTIFIER purely informational: reported, never decisive.
  2. A cited FILE existing and GATE-tracked was read as FIXED-leaning.
     Wrong for `engine/metta.pl` (P0.2b) and `examples/ch17-concurrency-and-the-loop/04-thin_forms.metta`
     (P1.1): plunit `consult`s every engine file transitively and test.sh
     globs every one of the 200 existing examples unconditionally, so BOTH
     were already GATE-tracked before Phase 0 or Phase 1 ever touched them.
     Fixed with TEST_SHAPED_ROOTS (only tests/, examples/, extensions/python/tests/,
     extensions/python/tools/ can count at all) COMBINED with excluding
     COLLECTOR_RUNNER_LABELS (a file swept in by a blanket pytest/plunit/
     example glob, or transitively loaded from one, does not count either;
     only a path check.sh's own lane text names LITERALLY does).
  3. A cited check.sh LANE existing as GATE was read as FIXED-leaning.
     Wrong for `vulture` (P2.7, "vulture's confidence floor" -- vulture
     has been a GATE lane since before P2.7 existed) and for `leatta`
     (P2.13, cited only as "the same differential pattern as the `leatta`
     lane," an analogy). Fixed by requiring the token's own PROVENANCE to
     be the item's terse "item" cell, not its longer acceptance/evidence
     prose, since an author citing an unrelated pre-existing lane only for
     comparison does so in the prose, never in the title.

What is left, after all three rounds, is deliberately narrow: a FILE or
LANE anchor stays bidirectional (missing/ungated is OPEN, present, GATE and
DELIBERATELY named is FIXED) because a path or a lane name has one
plausible referent and this tool can now tell a deliberate citation from an
incidental one. A PREDICATE or generic IDENTIFIER match is informational
only in both directions: reported, but it never decides an item, because
this spec is a maintenance plan against an EXISTING engine, and most names
it cites already exist regardless of which item is being asked about. Two
narrower EXCEPTIONS stay bidirectional because they are the sub-cases where
existence stops being ambiguous: an identifier `check_evidence_tags`
recognises as an actual pytest/plunit test NAME (long, hand-written,
written FOR the behaviour it pins, not a coincidental short word), and a
CODE-SHAPED span (an actual clause body, not a bare name) found verbatim in
this repository's own implementation source, which is asymmetric (a miss
proves nothing; a match, being long and structured, is unlikely to be
coincidental).

check_evidence_tags.py and evidence_runners.py already answer "does this
name exist, and does check.sh's GATE tier run it" for every pytest test,
plunit unit/test, Prolog check and example this tree ships; this module
reuses both rather than re-deriving check.sh's lane structure a second time.

Reads only. No engine, no janus, no `swipl`, no `pytest` subprocess: like
check_evidence_tags.py, this runs on a tree that does not boot.
Assumes:
  - ai-spec-execution.md sits one directory above the repository's MAIN
    checkout (not necessarily above `this` worktree), and the LeaTTa
    arbiter corpus one directory above THAT, per this workspace's own
    standing layout [source: the workspace CLAUDE.md, "Ledgers"
    and "the arbiter corpus", LeaTTa] [assumed 2026-08-18]
  - GFM table cells split on `|`, except one escaped as `\\|` or one that
    falls inside a matched run of backticks, which is how three of this
    spec's own rows carry a literal `|` (`shim.pl:92`'s `[F\\|Args]`, the
    MeTTa `\\|->` operator twice) without breaking their row's column count
    [source: https://github.github.com/gfm/#tables-extension-]
  - a cited `name/arity` or bare identifier's mere existence in this
    repository's own source is NOT decisive in either direction (see the
    three-round history above) [assumed 2026-08-18]
Guarantees:
  - every P<phase>.<n> id the spec's item tables define is reported exactly
    once, as FIXED, OPEN or UNKNOWN, with the anchor(s) that decided it
    [assumed 2026-08-18: verified by hand running
    tests/checks/check_spec_status_selftest.py, which is not yet wired into
    check.sh (single-owner) and so cannot be cited as "tested" until it
    is; the exact line is in this tool's own report]
  - an id the spec itself defines more than once with different row content
    is reported UNKNOWN and flagged ambiguous, never silently resolved to
    one of its rows [assumed 2026-08-18: same run as above]
  - a FIXED verdict flips to OPEN the moment the file or lane it names stops
    existing or stops being GATE-tier, and flips back the moment it returns
    [assumed 2026-08-18: same run as above, plus a live A/B against
    tests/shell/test_worktree_configuration.sh on the real tree]
Fails when:
  - an acceptance criterion states its target only in prose, with no
    backticked name. P9.3's own row is one such case: "a script asks the
    tree and prints FIXED/OPEN" names nothing checkable, so this tool
    reports P9.3 itself as UNKNOWN by the same rule as every other item,
    with no special case for its own existence
  - a numeric or measured claim ("50/236", "200 run") is the only content: this
    tool does not reproduce measurements, only structural existence and
    gating, so such an item resolves through whatever anchor its OTHER text
    separately names, or is UNKNOWN
  - a Prolog predicate or MeTTa symbol is defined dynamically (assert/1,
    string-built goals), under a spelling this tool's clause-head and
    equation-head regexes do not recognise, or under a name the spec's
    backticks do not quote exactly
  - a stale citation is quoted as part of describing its OWN resolution.
    P0.3's acceptance is "`translator.pl:40`'s citation of
    `tests/performance/reduce_dispatch.pl` IS RESOLVED," where the second
    path's correct, intended state is ABSENT (it was deleted as part of
    resolving the citation), so this tool's default polarity (a named file
    that does not exist is OPEN) reports P0.3 OPEN although it is in fact
    done. Recognising "a file named while describing a past citation's
    resolution should be absent" would need the same kind of polarity
    inference that produced the wrong answer for P2.1 during this file's
    own development (see extract_anchors); left as a known, named
    false-negative rather than a fourth heuristic
Decides:
  - which paths can ever earn a FIXED/OPEN file verdict: tests/, examples/,
    extensions/python/tests/, extensions/python/tools/ (TEST_SHAPED_ROOTS), and only when named
    literally rather than swept in by a blanket collector
    (COLLECTOR_RUNNER_LABELS)
  - a check.sh LANE anchor counts only when the item's own "item" cell
    names it, not its acceptance/evidence prose (resolve_lane)
  - a bare identifier shaped like `test_[a-z0-9_]+` (PYTEST_NAME, pytest's
    own collection convention) that resolves nowhere is OPEN; every other
    unresolved identifier or predicate is neutral, not OPEN
  - a Python reserved word (keyword.kwlist/softkwlist) is never treated as
    a checkable name
  - a token under three characters is never treated as a checkable
    identifier (too likely to be generic noise, e.g. "op")
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements:
    - a git-history check ("was this exact symbol/file absent at some
      reference commit and present now") would settle the "pre-existing
      vs newly built" question this file currently answers by staying
      silent on, for PREDICATE and generic IDENTIFIER anchors. Not built
      here because it needs a baseline commit choice that is not itself
      mechanical, and this file's own three-round history above shows that
      a plausible-looking heuristic in this exact spot is where the wrong
      answers came from
"""

from __future__ import annotations

import argparse
import json
import keyword
import re
import sys
from dataclasses import dataclass
from pathlib import Path

import check_evidence_tags as evidence_tags
from evidence_runners import COLLECTORS, LANE, ROOT, Execution, executed, gate_scripts


def _main_checkout(here: Path) -> Path:
    """The repository's PRIMARY checkout, even when `here` is a git-worktree
    copy of it (an isolated agent's own worktree, per this workspace's own
    convention: see the workspace CLAUDE.md and worktree.sh). A
    worktree's `.git` is a FILE, not a directory, reading
    `gitdir: <main>/.git/worktrees/<name>`; three parents up from that path
    is `<main>`, the same fact `worktree.sh` derives via `git worktree list`
    instead. ai-spec-execution.md is a single file shared by every worktree
    of this repository (it sits outside git entirely), so a worktree must
    resolve to the SAME spec path as the main checkout, not to a path
    relative to its own, isolated `.claude/worktrees/...` location.
    """
    git_path = here / ".git"
    if git_path.is_dir():
        return here
    if git_path.is_file():
        line = git_path.read_text(encoding="utf-8").strip()
        if line.startswith("gitdir:"):
            gitdir = Path(line.partition(":")[2].strip())
            if not gitdir.is_absolute():
                gitdir = (here / gitdir).resolve()
            return gitdir.parent.parent.parent
    return here


WORKSPACE = _main_checkout(ROOT).parent
SPEC_DEFAULT = WORKSPACE / "ai-spec-execution.md"

# ----------------------------------------------------------------- parsing
# A GFM pipe-table row: leading and trailing `|`, everything between split
# into cells. `ROW` only recognises the shape; `split_table_row` below does
# the splitting, because a naive `str.split("|")` breaks on this spec's own
# `` `T =.. [F\|Args]` `` and `` `\|->` `` cells (escaped pipes) and would
# have reported three rows here as malformed for no reason of the author's.
ROW = re.compile(r"^[ \t]*\|(.+)\|[ \t]*$")
SEPARATOR_CELL = re.compile(r"^:?-{2,}:?$")
ITEM_ID = re.compile(r"^P\d+\.\d+[a-z]?$")


def split_table_row(inner: str) -> list[str]:
    """Cells of one GFM table row, `inner` being the text between the outer
    pipes. A `|` counts as a delimiter unless it is escaped `\\|` or sits
    inside a run of backticks matched by an equal-length closing run, per
    the CommonMark table extension and code-span rules.
    """
    cells: list[str] = []
    current: list[str] = []
    i, n = 0, len(inner)
    in_code, fence_len = False, 0
    while i < n:
        ch = inner[i]
        if ch == "\\" and i + 1 < n and inner[i + 1] == "|" and not in_code:
            current.append("|")
            i += 2
            continue
        if ch == "`":
            j = i
            while j < n and inner[j] == "`":
                j += 1
            run_len = j - i
            if not in_code:
                in_code, fence_len = True, run_len
            elif run_len == fence_len:
                in_code, fence_len = False, 0
            current.append(inner[i:j])
            i = j
            continue
        if ch == "|" and not in_code:
            cells.append("".join(current))
            current = []
            i += 1
            continue
        current.append(ch)
        i += 1
    cells.append("".join(current))
    return [c.strip() for c in cells]


@dataclass(frozen=True)
class SpecRow:
    """One item row: its id, source line, and its "item"/"acceptance"-shaped
    cell texts. `evidence_text` is kept for display only and never mined for
    anchors (see module docstring).
    """

    id: str
    line: int
    header: tuple[str, ...]
    item_text: str
    acceptance_text: str
    evidence_text: str


def _column_role(header_name: str) -> str:
    """Which of this tool's three buckets a table column belongs to.

    "acceptance" covers a column literally named for it AND Phase 7's
    "target" (paired with "measured today", which is evidence-shaped and
    excluded the same as every other "evidence"). Everything else --
    partition codes, "why now", "source", "measured today" itself -- is
    excluded from anchor extraction, on the same reasoning as "evidence".
    """
    name = header_name.strip().lower()
    if name == "id":
        return "id"
    if name == "item":
        return "item"
    if "accept" in name or name == "target":
        return "acceptance"
    return "excluded"


def parse_tables(text: str) -> list[tuple[list[str], list[tuple[int, list[str]]]]]:
    """Every GFM pipe table in `text`: (header cells, [(1-based line, cells)]).

    A table is a `|...|` line immediately followed by a separator line of
    `---`/`:--:`-shaped cells, per the GFM table extension; that is the same
    signal a renderer uses, so this does not need a Markdown parser.
    """
    lines = text.splitlines()
    tables: list[tuple[list[str], list[tuple[int, list[str]]]]] = []
    i, n = 0, len(lines)
    while i < n:
        head = ROW.match(lines[i])
        nxt = ROW.match(lines[i + 1]) if i + 1 < n else None
        if head and nxt:
            sep_cells = split_table_row(nxt.group(1))
            if sep_cells and all(
                SEPARATOR_CELL.match(c.replace(" ", "")) for c in sep_cells if c
            ):
                header = split_table_row(head.group(1))
                rows = []
                j = i + 2
                while j < n and (row_match := ROW.match(lines[j])) is not None:
                    rows.append((j + 1, split_table_row(row_match.group(1))))
                    j += 1
                tables.append((header, rows))
                i = j
                continue
        i += 1
    return tables


def orphan_rows(text: str) -> list[str]:
    """Every `|...|` line that does NOT belong to a table.

    A blank line ENDS a GFM table, so rows written after one render as
    literal text with pipes rather than as table rows, and this tool never
    sees them either. Measured 2026-08-19: two blank lines had split Phase
    1's table and one had detached six of Phase 5's rows, and Phase 11's
    four items had no header row at all, so FIFTEEN items were invisible to
    the reader and to this tool at once. That is a worse failure than a
    duplicated id, which at least gets reported, so it is checked here
    beside it.
    """
    lines = text.splitlines()
    in_table: set[int] = set()
    for _, rows in parse_tables(text):
        in_table.update(line_no for line_no, _ in rows)
    headers: set[int] = set()
    for i in range(len(lines) - 1):
        head, nxt = ROW.match(lines[i]), ROW.match(lines[i + 1])
        if head and nxt:
            sep = split_table_row(nxt.group(1))
            if sep and all(SEPARATOR_CELL.match(c.replace(" ", "")) for c in sep if c):
                headers.add(i + 1)
    found = []
    for i, line in enumerate(lines, 1):
        match = ROW.match(line)
        if not match or i in in_table or i in headers:
            continue
        cells = split_table_row(match.group(1))
        if cells and all(SEPARATOR_CELL.match(c.replace(" ", "")) for c in cells if c):
            continue
        found.append(
            f"line {i}: a table row outside any table, so it renders as "
            f"literal text: {line.strip()[:60]}"
        )
    return found


def parse_items(text: str) -> tuple[dict[str, list[SpecRow]], list[str]]:
    """Every `P<phase>.<n>` item the spec's tables define, keyed by id (more
    than one entry means the spec itself defines that id more than once),
    plus structural warnings (a row whose cell count does not match its
    table's header, which this tool skips rather than misaligns).
    """
    items: dict[str, list[SpecRow]] = {}
    warnings: list[str] = []
    warnings.extend(orphan_rows(text))
    for header, rows in parse_tables(text):
        lower = [h.strip().lower() for h in header]
        if "id" not in lower or "item" not in lower:
            continue
        id_idx = lower.index("id")
        roles = [_column_role(h) for h in header]
        for line_no, cells in rows:
            if len(cells) != len(header):
                warnings.append(
                    f"line {line_no}: row has {len(cells)} cells against a "
                    f"{len(header)}-column header, skipped"
                )
                continue
            stripped = cells[id_idx].strip("*~ \t")
            if not ITEM_ID.match(stripped):
                continue
            by_role: dict[str, list[str]] = {"item": [], "acceptance": [], "excluded": []}
            for role, cell in zip(roles, cells, strict=True):
                by_role.setdefault(role, []).append(cell)
            row = SpecRow(
                id=stripped,
                line=line_no,
                header=tuple(header),
                item_text=" ".join(by_role["item"]),
                acceptance_text=" ".join(by_role["acceptance"]),
                evidence_text=" ".join(by_role["excluded"]),
            )
            items.setdefault(stripped, []).append(row)
    return items, warnings


# ----------------------------------------------------------------- anchors
# What one backtick span can be, in ascending order of how much a match
# means. Checked in this order because a Prolog indicator `foo/2` also
# matches the file pattern's "contains a slash" branch.
BACKTICK = re.compile(r"`([^`]+)`")
PREDICATE_TOKEN = re.compile(r"^[a-z][A-Za-z0-9_]*(?::[a-z][A-Za-z0-9_]*)?/\d+$")
FILE_EXTENSIONS = (
    "py", "pl", "plt", "metta", "sh", "md", "toml", "json", "rs", "c", "cfg",
    "yml", "yaml", "txt", "cff",
)
FILE_TOKEN = re.compile(
    r"^(?P<path>(?:[\w.-]+/)+[\w.-]+|\w[\w.-]*\.(?:" + "|".join(FILE_EXTENSIONS) + r"))"
    r"(?::(?P<lines>\d+(?:[-,]\d+)*))?$"
)
IDENTIFIER_TOKEN = re.compile(r"^[A-Za-z_][A-Za-z0-9_./:!?-]*$")
# pytest's own collection convention (python_functions' documented default,
# "test*"), used in resolve_identifier to tell "this names one specific,
# not-yet-written test" from "this is a bare word with no clear referent".
PYTEST_NAME = re.compile(r"^test_[A-Za-z0-9_]+$")
# A code-shaped span: a literal fragment of Prolog or Python offered as the
# fixed form, e.g. P1.13's `( retract(Head) -> Removed = true ; Removed = false )`.
# Distinguished from a MeTTa runtime expression like `(only-a B)` (P3.1's
# evidence) by requiring a control/assignment operator alongside a paren;
# bare MeTTa data never matches and is silently skipped, which is safe
# because a found/not-found code-shape signal is asymmetric (see below).
CODE_SHAPED = re.compile(r"[(].*(?::-|->|;|=)|(?::-|->|;|=).*[(]")
# Reserved words are never a definition's name in any of Prolog, Python or
# MeTTa's own special-form set, so "found" or "not found" says nothing.
# Python's own keyword list is used rather than a hand-picked stoplist,
# because it is authoritative and exhaustive rather than guessed.
NOT_A_NAME = frozenset(keyword.kwlist) | frozenset(keyword.softkwlist)


@dataclass(frozen=True)
class Anchor:
    """One checkable thing a backtick span named, and where it came from."""

    kind: str  # "file" | "predicate" | "lane" | "identifier"
    token: str
    provenance: str  # "item" | "acceptance": which column named it
    line_ref: str | None = None  # a cited "123" or "123-456", file anchors only


def classify_token(token: str) -> str | None:
    """Which anchor kind a backtick span names, or None for prose, an
    operator symbol, a MeTTa runtime expression, or a variable.
    """
    token = token.strip()
    if not token or any(c.isspace() for c in token):
        return None
    if token[0] in "([!$%@&#<>=*+":
        return None
    if PREDICATE_TOKEN.match(token):
        return "predicate"
    m = FILE_TOKEN.match(token)
    if m:
        return "file"
    if len(token) < 3:
        return None
    if token in NOT_A_NAME:
        return None
    if IDENTIFIER_TOKEN.match(token) and any(c.isalpha() for c in token):
        return "identifier"
    return None


def extract_anchors(row: SpecRow) -> list[Anchor]:
    """Every checkable anchor named in `row`'s item and acceptance text, in
    that order, deduplicated by (kind, token).

    An earlier version of this function also inverted an anchor's polarity
    on a negation cue ("stops being", "no longer" next to the name), on the
    theory that "`fun_here/1` stops being consulted at pattern positions"
    (P2.1) means the fix is proven by `fun_here/1`'s ABSENCE. Run against
    the real spec, that inversion produced a confident but WRONG "OPEN"
    verdict for P2.1: `fun_here/1` is a predicate that keeps existing after
    the fix (Phase 2 only changes where it is consulted, a call-site
    question this tool cannot see), so checking its existence answers a
    different question than the one the cue describes, in either polarity.
    Removed rather than tuned further, because the mismatch is between
    WHAT is checked (existence) and WHAT the sentence claims (usage), and no
    amount of cue-list tuning fixes that gap [measured 2026-08-18: running
    this tool with the earlier version against the live spec].
    """
    seen: set[tuple[str, str]] = set()
    anchors: list[Anchor] = []
    for provenance, source in (("item", row.item_text), ("acceptance", row.acceptance_text)):
        for span in BACKTICK.findall(source):
            kind = classify_token(span)
            if kind is None or (kind, span) in seen:
                continue
            seen.add((kind, span))
            line_ref = None
            token = span
            if kind == "file":
                m = FILE_TOKEN.match(span)
                assert m is not None, "classify_token returned 'file' without a FILE_TOKEN match"
                token, line_ref = m.group("path"), m.group("lines")
            anchors.append(Anchor(kind, token, provenance, line_ref))
    return anchors


def extract_code_spans(row: SpecRow) -> list[str]:
    """Every backtick span in `row`'s item/acceptance text that looks like
    Prolog or Python code rather than a name. Unlike `Anchor`, a code span
    carries no provenance: `resolve_code_span` treats an item- and an
    acceptance-column snippet identically, so there is nothing to carry.
    """
    spans = []
    for source in (row.item_text, row.acceptance_text):
        for span in BACKTICK.findall(source):
            if classify_token(span) is None and CODE_SHAPED.search(span) and len(span) >= 6:
                spans.append(span)
    return spans


# ------------------------------------------------------------- tree facts
PROLOG_DIRS = ("engine", "lib", "extensions/mork", "extensions/mork/mork_ffi", "extensions/python/metta", "tests")
METTA_DIRS = ("lib", "examples", "extensions/python/examples", "tests")
PYTHON_DIRS = ("extensions/python/metta", "extensions/python/tools", "extensions/python/examples", "extensions/python/benchmarks")
IMPLEMENTATION_DIRS = ("engine", "lib", "extensions/mork", "extensions/mork/mork_ffi", "extensions/python/metta")

PROLOG_CLAUSE_HEAD = re.compile(r"^([a-z][A-Za-z0-9_]*)\(", re.MULTILINE)
PROLOG_DECLARATION = re.compile(
    r":-\s*(?:dynamic|multifile|discontiguous)\s+([a-zA-Z_]\w*)/(\d+)"
)
METTA_HEAD = re.compile(r"\(\s*(?:=|:)\s*\(?\s*([A-Za-z_][\w!?-]*)")
PYTHON_DEF = re.compile(r"^\s*(?:async\s+)?def\s+([A-Za-z_]\w*)\s*\(", re.MULTILINE)
PYTHON_CLASS = re.compile(r"^\s*class\s+([A-Za-z_]\w*)\s*[(:]", re.MULTILINE)
PYTHON_CONST = re.compile(r"^([A-Z_][A-Z0-9_]*)\s*(?::[^=\n]+)?=[^=]", re.MULTILINE)

WHITESPACE = re.compile(r"\s+")


def _read_paren_arity(text: str, open_idx: int) -> int:
    """Argument count of the `(...)` starting at `text[open_idx]`, skipping
    nested brackets and quoted atoms/strings so a comma inside `'a,b'` is
    not counted. Returns -1 if the group never closes (truncated file).
    """
    depth, arity, i, n, quote = 0, 1, open_idx, len(text), None
    while i < n:
        ch = text[i]
        if quote:
            if ch == "\\" and i + 1 < n:
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in "'\"":
            quote = ch
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth == 0:
                return arity
        elif ch == "," and depth == 1:
            arity += 1
        i += 1
    return -1


def _files(dirs: tuple[str, ...], pattern: str) -> list[Path]:
    seen: set[Path] = set()
    found: list[Path] = []
    for rel in dirs:
        base = ROOT / rel
        if not base.is_dir():
            continue
        for path in sorted(base.rglob(pattern)):
            if path.is_symlink() or "__pycache__" in path.parts:
                continue
            resolved = path.resolve()
            if resolved not in seen:
                seen.add(resolved)
                found.append(path)
    return found


def _index_prolog() -> dict[str, list[tuple[Path, int, int]]]:
    index: dict[str, list[tuple[Path, int, int]]] = {}
    for path in _files(PROLOG_DIRS, "*.pl") + _files(PROLOG_DIRS, "*.plt"):
        text = path.read_text(encoding="utf-8", errors="replace")
        for match in PROLOG_CLAUSE_HEAD.finditer(text):
            arity = _read_paren_arity(text, match.end() - 1)
            if arity < 0:
                continue
            line = text.count("\n", 0, match.start()) + 1
            index.setdefault(match.group(1), []).append((path, line, arity))
        for match in PROLOG_DECLARATION.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            index.setdefault(match.group(1), []).append((path, line, int(match.group(2))))
    return index


def _index_metta() -> dict[str, list[tuple[Path, int]]]:
    index: dict[str, list[tuple[Path, int]]] = {}
    for path in _files(METTA_DIRS, "*.metta"):
        text = path.read_text(encoding="utf-8", errors="replace")
        for match in METTA_HEAD.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            index.setdefault(match.group(1), []).append((path, line))
    return index


def _index_python() -> dict[str, list[tuple[Path, int, str]]]:
    index: dict[str, list[tuple[Path, int, str]]] = {}
    for path in _files(PYTHON_DIRS, "*.py"):
        text = path.read_text(encoding="utf-8", errors="replace")
        for regex, kind in ((PYTHON_DEF, "def"), (PYTHON_CLASS, "class"), (PYTHON_CONST, "const")):
            for match in regex.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                index.setdefault(match.group(1), []).append((path, line, kind))
    return index


def _lane_tiers() -> dict[str, str]:
    """Every lane the gate declares, and the tier it runs in.

    Root and components alike: a lane's tier is not changed by which file
    carries it, and an item anchored on a lane the root gate no longer spells
    would otherwise read UNKNOWN rather than FIXED [measured 2026-08-28: 28 of
    the 80 lanes moved into extensions/python/check.sh in one commit].
    """
    tiers: dict[str, str] = {}
    for script in gate_scripts():
        text = script.read_text(encoding="utf-8", errors="replace")
        tiers |= {name: tier for tier, name, _ in LANE.findall(text)}
    return tiers


@dataclass(frozen=True)
class TreeFacts:
    """Everything gathered from the repository once, up front, and handed to
    every `resolve_*` function; nothing below this point reads a file.
    """

    lanes: dict[str, str]
    runs: dict[Path, Execution]
    evidence: evidence_tags.Evidence
    prolog_defs: dict[str, list[tuple[Path, int, int]]]
    metta_defs: dict[str, list[tuple[Path, int]]]
    python_defs: dict[str, list[tuple[Path, int, str]]]
    implementation_text: str


def gather_tree_facts() -> TreeFacts:
    """Everything the verdict engine asks the repository for, computed once.
    Every piece here is a plain read: file globs, regex scans, and the two
    sibling modules' own (also read-only) `executed()`/`gather()`.
    """
    runs, _problems = executed()
    evidence, _problems2 = evidence_tags.gather()
    impl_chunks = [
        p.read_text(encoding="utf-8", errors="replace") for p in _files(IMPLEMENTATION_DIRS, "*.pl")
    ] + [p.read_text(encoding="utf-8", errors="replace") for p in _files(IMPLEMENTATION_DIRS, "*.py")]
    return TreeFacts(
        lanes=_lane_tiers(),
        runs=runs,
        evidence=evidence,
        prolog_defs=_index_prolog(),
        metta_defs=_index_metta(),
        python_defs=_index_python(),
        implementation_text=WHITESPACE.sub("", "".join(impl_chunks)),
    )


# ---------------------------------------------------------------- verdicts
@dataclass(frozen=True)
class Verdict:
    """What one anchor decided, and the human-readable reason why."""

    status: str | None  # "fixed" | "open" | None (neutral: no opinion)
    detail: str


# Roots under which a file is something BUILT to demonstrate one item: a
# test, a fixture, an example, or a single-purpose check script. A file
# under an IMPLEMENTATION root (engine/, lib/, extensions/mork/,
# extensions/python/metta/) is excluded on purpose: `evidence_runners.executed()`
# marks engine/metta.pl GATE because plunit `consult`s it transitively, which
# is true of almost every engine file whether or not any given item ever
# touched it, so "exists and is GATE-tracked" is true of engine/metta.pl both
# before P0.2b's fix and after it and says nothing about P0.2b specifically
# [measured 2026-08-18: running this tool's earlier version against the
# live spec gave P0.2b, P2.5, P2.8, P2.9 and others a FIXED verdict purely
# because their cited predicate/file predates the item that cites it].
TEST_SHAPED_ROOTS = tuple(
    Path(root).parts for root in ("tests", "examples", "extensions/python/tests", "extensions/python/tools")
)

# The three collectors are BLANKET globs: `extensions/python/tests/test_*.py`,
# `tests/prolog/*.plt` and (via test.sh) every `examples/**/*.metta` are ALL
# swept in unconditionally, so "this file is under a test-shaped root and is
# GATE-tracked" is true of EVERY existing test and EVERY one of the 200
# existing examples, whether or not the citing item ever touched it.
# `examples/ch17-concurrency-and-the-loop/04-thin_forms.metta` is P1.1's own worked example: the item
# CORRECTS its prose, it does not create the file, so the file already
# existed and was already gate-tracked before Phase 1 ever started
# [measured 2026-08-18: the earlier version called P1.1 FIXED on exactly
# this evidence, while the base commit predates Phase 1 entirely]. A file
# reached only through a Collector, or transitively loaded FROM one (an
# engine file `consult`ed by a swept-in test), inherits the same blindness
# and is excluded here too. What remains strong is a file check.sh's own
# lane text names LITERALLY, one path at a time (`tests/
# test_worktree_configuration.sh`, `extensions/python/tools/example_parity.py`): each
# such line was added deliberately, for one check, which a blanket glob is
# not.
COLLECTOR_RUNNER_LABELS = frozenset(f"{c.runner}: {c.lane}" for c in COLLECTORS)


def _is_test_shaped(path: Path) -> bool:
    try:
        rel_parts = path.resolve().relative_to(ROOT).parts
    except ValueError:
        return False
    return any(rel_parts[: len(root)] == root for root in TEST_SHAPED_ROOTS)


# Every literal root a cited path is checked against, outermost fallback
# last. WORKSPACE.parent is the workspace's own parent, derived the same
# worktree-safe way WORKSPACE is (never a literal `/home` path in this
# file): the historical `LeaTTa` corpus sits there, and the ledgers'
# older acceptance records still cite into it; P2.13's acceptance cites
# `LeaTTa/MeTTaILProofs/CPExecutable.lean` directly. Checking ROOT and
# WORKSPACE only reported that file "absent" when it exists one directory
# further out [measured 2026-08-18].
SEARCH_ROOTS = (ROOT, WORKSPACE, WORKSPACE.parent)


def _locate_file(token: str) -> list[Path]:
    """Where a cited path actually lives. Checked literally against each of
    SEARCH_ROOTS in turn. A BARE filename with no `/` -- P0.2a's `shim.pl`,
    meaning `extensions/python/metta/shim.pl` -- is resolved by searching the TREE
    (ROOT only; WORKSPACE and its siblings are not this tool's to walk) for
    that exact basename, because the spec cites many files by their last
    path component only, and checking only `ROOT / token` reported
    `shim.pl` as absent when `extensions/python/metta/shim.pl` was sitting right there
    [measured 2026-08-18].
    """
    for root in SEARCH_ROOTS:
        candidate = root / token
        if candidate.exists():
            return [candidate]
    if "/" in token:
        return []
    return [
        p for p in ROOT.rglob(token)
        if not p.is_symlink() and not _transient(p.parts)
    ]


#`.claude/worktrees/` holds one full copy of the tree per isolated agent and
#`ai-tmp/` holds project-local scratch, so a bare basename matched 15 copies of
#tests/prolog/static_checks.pl and resolve_file/2 called the result "ambiguous"
#because the copies disagreed with each other [measured 2026-08-19, P0.12].
#Neither directory is part of the tree this document describes.
_TRANSIENT = frozenset({".git", "__pycache__", ".claude", "ai-tmp", "build", ".venv"})


def _transient(parts: tuple[str, ...]) -> bool:
    """Whether a path lies in a directory that is a COPY of the tree or
    scratch beside it, rather than the tree itself.
    """
    return any(part in _TRANSIENT for part in parts)


def _shown_path(location: Path) -> str:
    """`location` relative to whichever SEARCH_ROOTS entry contains it, so
    a report line never leaks this machine's absolute layout.
    """
    for label, root in (("", ROOT), ("WORKSPACE/", WORKSPACE), ("WORKSPACE/../", WORKSPACE.parent)):
        if location.is_relative_to(root):
            return f"{label}{location.relative_to(root)}"
    return str(location)


def _file_outcome(path: Path, facts: TreeFacts) -> tuple[str | None, str]:
    """(status, why) for a file this tool located. FIXED needs a
    test/example-shaped path, GATE tracking, AND a lane that names it
    LITERALLY rather than sweeping it in by a blanket pytest/plunit/example
    glob (see COLLECTOR_RUNNER_LABELS above); a test-shaped, literally-named
    path that only a REPORT lane reaches is OPEN (named but not yet gated,
    per this project's own V1: not done until the gate is green); anything
    under an implementation root, blanket-swept, or untracked by any
    runner, is neutral.
    """
    if path.is_dir():
        return None, "exists as a directory"
    execution = facts.runs.get(path.resolve())
    if execution is None:
        return None, "exists, but is not a test/example any runner executes; existence alone does not confirm the change"
    deliberate = _is_test_shaped(path) and execution.runner not in COLLECTOR_RUNNER_LABELS
    if execution.tier == "GATE":
        if deliberate:
            return "fixed", f"exists, run by {execution.runner} as GATE"
        return None, (
            f"exists, run by {execution.runner} as GATE, but only via a blanket "
            f"pytest/plunit/example collector or a transitive load from one, or "
            f"sits under an implementation root; existence alone predates most "
            f"fixes and is not decisive"
        )
    status = "open" if deliberate else None
    return status, f"exists but only {execution.runner} runs it (REPORT, not gated)"


def resolve_file(anchor: Anchor, facts: TreeFacts) -> Verdict:
    """Locate `anchor.token` and score what was found, per `_file_outcome`."""
    candidates = _locate_file(anchor.token)
    if not candidates:
        return Verdict(
            "open",
            f"`{anchor.token}` does not exist under this repository, the workspace, "
            f"or a sibling of it (checked: {', '.join(_shown_path(r) or '.' for r in SEARCH_ROOTS)})",
        )
    outcomes = [_file_outcome(path, facts) for path in candidates]
    statuses = {status for status, _ in outcomes}
    if len(statuses) > 1:
        return Verdict(
            None,
            f"`{anchor.token}` matches {len(candidates)} files by basename with "
            f"conflicting signals ({sorted(s or 'neutral' for s in statuses)}); ambiguous",
        )
    status, why = outcomes[0]
    return Verdict(status, f"`{anchor.token}` ({_shown_path(candidates[0])}) {why}")


def resolve_lane(anchor: Anchor, facts: TreeFacts) -> Verdict | None:
    """check.sh lane names are a small, deliberately-curated, enumerable
    set (unlike a bare predicate or Python name), so a hit or a miss here
    stays fully bidirectional -- there is no "pre-existing lane that
    happens to share this name" risk the way there is for `swrite` or
    `register_op` -- PROVIDED the item's own ITEM column names it, not only
    its acceptance criterion.

    Two confirmed counterexamples, both in the ACCEPTANCE column, both
    fixed by requiring `provenance == "item"` rather than by a word-cue
    [measured 2026-08-18]:
      - P2.7 names `vulture`'s confidence floor, never "the `vulture`
        lane": `vulture` has been a GATE lane since before P2.7 existed, so
        treating its mere existence as evidence called P2.7 done regardless
        of whether its real claims (a derived delimiter rule, a deleted
        dead variable, a lowered threshold) had landed. Requiring the
        SENTENCE to contain the word "lane" was tried first and did not
        catch this, because "confidence floor" carries no such word.
      - P2.13 cites "the same differential pattern as the `leatta`
        conformance lane" as an ANALOGY for a new Lean cross-check, and
        DOES contain the word "lane" right there, so the word-cue version
        of this check accepted it -- `leatta` predates Phase 2 entirely, so
        this was the same false signal in a form the word-cue could not
        see either.
    An item's ITEM cell is its terse, title-like description of what the
    item IS; an author citing an unrelated EXISTING lane only as a
    comparison does so in the longer, discursive acceptance/evidence prose,
    never in that terse cell, in every case checked here.
    """
    tier = facts.lanes.get(anchor.token)
    if tier is None:
        return None
    if anchor.provenance != "item":
        return Verdict(
            None,
            f"`{anchor.token}` is a check.sh lane (tier {tier}), but only the "
            f"acceptance/evidence prose names it, not the item's own title cell; "
            f"a lane that predates this item proves nothing about it by existing",
        )
    status = "fixed" if tier == "GATE" else "open"
    return Verdict(status, f"`{anchor.token}` is a check.sh lane, tier {tier}")


def resolve_predicate(anchor: Anchor, facts: TreeFacts) -> Verdict:
    """A `name/arity` indicator is informational ONLY: most of this spec's
    citations name a predicate the ENGINE ALREADY HAS (P2.5's `swrite/2`,
    P2.8's `fun/1`), so existence alone is true before the item's fix as
    often as after it [measured 2026-08-18, same run noted on
    TEST_SHAPED_ROOTS above]. Absence is even weaker: the name may be a
    SWI or library builtin the fix CALLS (P1.13's `retract/1`) rather than
    a symbol it DEFINES. Neither direction moves an item's verdict; both
    are still reported, so a human reading `--id` output sees what this
    tool saw.
    """
    name, _, cited_arity = anchor.token.partition("/")
    name = name.split(":")[-1]
    found = facts.prolog_defs.get(name, [])
    exact = [f for f in found if f[2] == int(cited_arity)]
    if exact:
        path, line, _ = exact[0]
        return Verdict(None, f"`{anchor.token}` defined at {path.relative_to(ROOT)}:{line} (existence alone is not decisive, see Assumes)")
    if found:
        arities = sorted({f[2] for f in found})
        return Verdict(None, f"`{name}` exists but not at arity {cited_arity} (found arities {arities})")
    return Verdict(None, f"`{anchor.token}` not found as a clause head in {', '.join(PROLOG_DIRS)}; may be a builtin the fix calls rather than defines")


def _identifier_targets(name: str, facts: TreeFacts) -> list[str]:
    where = []
    if name in facts.prolog_defs:
        where.append(f"Prolog predicate at {facts.prolog_defs[name][0][0].relative_to(ROOT)}:{facts.prolog_defs[name][0][1]}")
    if name in facts.metta_defs:
        where.append(f"MeTTa head at {facts.metta_defs[name][0][0].relative_to(ROOT)}:{facts.metta_defs[name][0][1]}")
    if name in facts.python_defs:
        path, line, kind = facts.python_defs[name][0]
        where.append(f"Python {kind} at {path.relative_to(ROOT)}:{line}")
    return where


def resolve_identifier(anchor: Anchor, facts: TreeFacts) -> Verdict:
    """Two tiers, matching `resolve_predicate`'s reasoning. A name
    `check_evidence_tags` already knows as a real pytest/plunit/example
    name is a NARROW, ENUMERABLE universe (every test this tree ships), so
    a hit or a miss THERE stays bidirectional. A name only found by this
    tool's own broad "does it appear as a def/class/predicate/equation
    head anywhere" scan is informational only, for the same reason
    `resolve_predicate` is: `register_op`, `Expr`, `m.eval`'s `eval` and
    most other names in this spec already existed before the item that
    cites them, and for a RENAME item (P10.4, P10.5) finding the OLD name
    still defined is not even weak evidence of progress, it is what
    "not yet renamed" looks like [measured 2026-08-18: the earlier version
    called P10.5 FIXED because `m.space_name` -- the name being RETIRED --
    was still findable, which is backwards].

    Within `check_evidence_tags`'s own universe, "prolog"-kind targets are
    excluded from the bidirectional path and folded into the informational
    one: that kind is a BROAD sweep of every clause-head-shaped name under
    tests/ (`check_evidence_tags._prolog_targets`'s own regex over every
    name starting a Prolog clause or fact), so it registered
    an unrelated fixture predicate literally called `quote` inside
    tests/prolog/reachability.pl and made that predicate's existence read as
    P2.3's own evidence, though P2.3 is about the MeTTa special form
    [measured 2026-08-18]. "pytest" and "plunit" kinds are long, specific,
    hand-written identifiers this project names FOR the behaviour they pin
    (`test_the_grouping_is_preserved`), which is a different, much lower
    collision risk, so those stay bidirectional.

    A plunit UNIT is deliberately NOT in that set, though every test inside
    one is. A unit is named for the MODULE it covers rather than for a single
    behaviour, which puts it back in the `quote` fixture's collision class: of
    the three unit-only names this spec cites, `lib_tabling` and `lib_thread`
    appear in P1.14's and P12.16's problem text meaning the LIBRARIES
    lib/lib_tabling and lib/lib_thread, and only P1.30's
    `parser_nonfinite_print` means the unit. All three items also cite a
    `test_` anchor, and that is what decides them, so excluding units costs no
    verdict and drops two false witnesses [measured 2026-08-31: adding
    "plunit-unit" to this set changes no FIXED/OPEN/UNKNOWN verdict and only
    moves P1.14 and P12.16 onto the library-shaped name; commit=WORKTREE].
    """
    token = anchor.token
    candidates = [token] + ([token.rsplit(".", 1)[-1]] if "." in token else [])
    resolved = evidence_tags.resolve(token, facts.evidence)
    if isinstance(resolved, list) and resolved:
        specific = [t for t in resolved if t.kind in ("pytest", "plunit")]
        if specific:
            # An EMPTY list means the token's shape (typically hyphenated,
            # like `get-type`) falls outside resolve()'s own IDENTIFIER
            # pattern: that is "not asked," not "not found," so it falls
            # through below, same as resolve() returning a "not found"
            # string does.
            problems = [evidence_tags.target_problem(token, t, facts.evidence) for t in specific]
            if any(p is None for p in problems):
                return Verdict("fixed", f"`{token}` is a known, GATE-run pytest/plunit test")
            return Verdict("open", f"`{token}`: {problems[0]}")
        kinds = sorted({t.kind for t in resolved})
        if "plunit-unit" in kinds:
            # Not the broad sweep: a unit is a real, hand-written name, and
            # saying otherwise sends a reader looking for a stray fixture.
            return Verdict(
                None,
                f"`{token}` names a plunit UNIT rather than one of its tests, and a unit "
                f"is named for the module it covers, so this may be that module's own "
                f"name in prose; name a test inside it to decide this item",
            )
        return Verdict(
            None,
            f"`{token}` matches only {kinds} in check_evidence_tags' broad sweep "
            f"(not a specific pytest/plunit test name); may be a coincidental "
            f"same-named fixture rather than evidence for this item",
        )
    for name in candidates:
        where = _identifier_targets(name, facts)
        if where:
            return Verdict(None, f"`{token}` found as {where[0]} (existence alone is not decisive, see Assumes)")
    if PYTEST_NAME.match(token):
        # `test_` is pytest's OWN collection convention (pytest.ini_options'
        # python_functions default, re-checked by PYTEST_DISCOVERY_KEYS in
        # evidence_runners.py), not a heuristic invented here: a token
        # SHAPED this way is unambiguously meant to be one specific test
        # function, unlike a bare word such as `atomically` or `switch`
        # that could be prose, a builtin, or simply not-yet-conventional.
        # Absent from BOTH check_evidence_tags' universe and this tool's own
        # def/class/predicate scan, it is a named test that does not exist.
        return Verdict("open", f"`{token}` looks like a pytest test name and is not defined anywhere in the tree")
    return Verdict(None, f"`{token}` not found as a Prolog/MeTTa/Python definition (may be external, a keyword-adjacent word, or spelled differently)")


def resolve_code_span(snippet: str, facts: TreeFacts) -> Verdict:
    """Asymmetric on purpose: a long, structured code fragment (an actual
    clause body, not a bare name) matching verbatim after whitespace is
    stripped is unlikely to be a coincidence, so a MATCH is real FIXED-
    leaning evidence. A miss proves nothing (formatting drift, a renamed
    variable), so it stays neutral rather than becoming a false OPEN.
    """
    normalized = WHITESPACE.sub("", snippet)
    if normalized and normalized in facts.implementation_text:
        return Verdict("fixed", f"the exact code `{snippet}` appears verbatim in {', '.join(IMPLEMENTATION_DIRS)}")
    return Verdict(None, f"code span `{snippet}` not found verbatim (formatting may differ; not evidence either way)")


def resolve_anchor(anchor: Anchor, facts: TreeFacts) -> Verdict:
    """Dispatch to the one `resolve_*` function matching `anchor.kind`."""
    if anchor.kind == "file":
        return resolve_file(anchor, facts)
    if anchor.kind == "predicate":
        return resolve_predicate(anchor, facts)
    if anchor.kind == "identifier":
        lane = resolve_lane(anchor, facts)
        return lane if lane is not None else resolve_identifier(anchor, facts)
    raise AssertionError(f"unhandled anchor kind {anchor.kind!r}")


# ------------------------------------------------------------------ items
@dataclass(frozen=True)
class ItemStatus:
    """The final, reported verdict for one spec item id."""

    id: str
    status: str  # "FIXED" | "OPEN" | "UNKNOWN"
    reasons: tuple[str, ...]
    ambiguous: bool
    anchors_considered: int


def _evaluate_ambiguous(rows: list[SpecRow], facts: TreeFacts) -> ItemStatus:
    """The spec itself defines this id more than once (Phase 4's own
    P4.1-P4.7 duplication): report each row's own leaning for a human to
    disambiguate, but never guess which row governs.
    """
    per_row = []
    for row in rows:
        row_verdicts = [resolve_anchor(a, facts) for a in extract_anchors(row)]
        leaning = {v.status for v in row_verdicts if v.status}
        per_row.append(f"line {row.line}: {sorted(leaning) or 'no anchor'}")
    return ItemStatus(
        rows[0].id, "UNKNOWN",
        (f"ambiguous id: the spec defines {rows[0].id} {len(rows)} times with different "
         f"content ({'; '.join(per_row)}); this tool refuses to guess which row governs",),
        True, 0,
    )


def _evaluate_single(row: SpecRow, facts: TreeFacts) -> ItemStatus:
    """OPEN if any anchor is OPEN, else FIXED if any is FIXED, else UNKNOWN
    -- naming whether any anchor was found at all, since that distinction
    (no anchor named vs. anchors named but all inconclusive) is itself part
    of this tool's honesty about what it can decide.
    """
    anchors = extract_anchors(row)
    verdicts = [(a, resolve_anchor(a, facts)) for a in anchors]
    code_verdicts = [(s, resolve_code_span(s, facts)) for s in extract_code_spans(row)]
    opens = [v.detail for _, v in verdicts if v.status == "open"]
    fixeds = [v.detail for _, v in verdicts if v.status == "fixed"] + [
        v.detail for _, v in code_verdicts if v.status == "fixed"
    ]
    considered = len(anchors) + len(code_verdicts)
    if opens:
        return ItemStatus(row.id, "OPEN", tuple(opens), False, considered)
    if fixeds:
        return ItemStatus(row.id, "FIXED", tuple(fixeds), False, considered)
    if considered:
        inconclusive = [v.detail for _, v in verdicts] + [v.detail for _, v in code_verdicts]
        return ItemStatus(row.id, "UNKNOWN", tuple(inconclusive), False, considered)
    return ItemStatus(
        row.id, "UNKNOWN",
        ("acceptance criterion (and item text) name no file, predicate, lane, or "
         "identifier this tool can check",),
        False, 0,
    )


def evaluate_item(rows: list[SpecRow], facts: TreeFacts) -> ItemStatus:
    """One id's verdict: `_evaluate_ambiguous` if the spec defines the id
    more than once, otherwise `_evaluate_single`.
    """
    if len(rows) > 1:
        return _evaluate_ambiguous(rows, facts)
    return _evaluate_single(rows[0], facts)


def _phase_key(item_id: str) -> tuple[int, str]:
    phase, _, rest = item_id[1:].partition(".")
    return int(phase), rest


# --------------------------------------------------------------------- CLI
def _select_ids(statuses: dict[str, ItemStatus], phase: str | None, only_id: str | None) -> list[str]:
    """Every id to report, sorted by phase then number, narrowed by
    --phase/--id. Raises `KeyError(only_id)` if --id names an unknown id,
    for `main` to turn into a clean error rather than an empty report.
    """
    selected = sorted(statuses, key=_phase_key)
    if phase:
        prefix = phase if phase.startswith("P") else f"P{phase}"
        selected = [i for i in selected if i == prefix or i.startswith(prefix + ".")]
    if only_id:
        if only_id not in statuses:
            raise KeyError(only_id)
        selected = [only_id]
    return selected


def _json_payload(spec: Path, items: dict[str, list[SpecRow]], warnings: list[str],
                   statuses: dict[str, ItemStatus], selected: list[str]) -> dict:
    """The --json shape: enough for a script (or check_spec_status_selftest.py)
    to assert on exact verdicts without parsing the human-readable report.
    """
    return {
        "spec": str(spec),
        "total_rows": sum(len(v) for v in items.values()),
        "distinct_ids": len(items),
        "warnings": warnings,
        "items": [
            {
                "id": statuses[i].id,
                "status": statuses[i].status,
                "reasons": list(statuses[i].reasons),
                "ambiguous": statuses[i].ambiguous,
                "anchors_considered": statuses[i].anchors_considered,
            }
            for i in selected
        ],
    }


def _print_report(statuses: dict[str, ItemStatus], selected: list[str], verbose: bool) -> None:
    """One line per item (`id  STATUS  reason`), or full detail under
    --id/--phase (`verbose`): every reason on its own line.
    """
    for item_id in selected:
        s = statuses[item_id]
        if verbose:
            print(f"{s.id}  {s.status}" + ("  (ambiguous id)" if s.ambiguous else ""))
            for reason in s.reasons:
                print(f"    - {reason}")
            continue
        reason = s.reasons[0] if s.reasons else ""
        if len(s.reasons) > 1:
            reason += f"  (+{len(s.reasons) - 1} more)"
        print(f"{s.id}\t{s.status}\t{reason}")


def _print_summary(items: dict[str, list[SpecRow]], warnings: list[str], statuses: dict[str, ItemStatus]) -> None:
    """The closing tally: how many ids, how many duplicated, and -- the
    number this task asked for -- how many of them this tool can decide.
    """
    for warning in warnings:
        print(f"WARNING (spec table): {warning}")

    total_rows = sum(len(v) for v in items.values())
    duplicated = sorted(i for i, rows in items.items() if len(rows) > 1)
    counts = {"FIXED": 0, "OPEN": 0, "UNKNOWN": 0}
    zero_anchor = 0
    for s in statuses.values():
        counts[s.status] += 1
        if s.status == "UNKNOWN" and s.anchors_considered == 0 and not s.ambiguous:
            zero_anchor += 1
    decidable = counts["FIXED"] + counts["OPEN"]
    print(
        f"\n{total_rows} item rows parsed into {len(items)} distinct ids "
        f"({len(duplicated)} duplicated: {' '.join(duplicated)})"
    )
    print(f"FIXED {counts['FIXED']}, OPEN {counts['OPEN']}, UNKNOWN {counts['UNKNOWN']}")
    print(
        f"decidable (FIXED+OPEN) = {decidable} / {len(items)} = {100 * decidable / len(items):.1f}%; "
        f"of the {counts['UNKNOWN']} UNKNOWN, {zero_anchor} name no checkable anchor at all and "
        f"{counts['UNKNOWN'] - zero_anchor - len(duplicated)} had anchors that all resolved inconclusive"
    )


def main(argv: list[str] | None = None) -> int:
    """CLI entry point: parse the spec, ask the tree, print one line per
    item (or one item's full detail under --id), then a summary.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--spec", type=Path, default=SPEC_DEFAULT, help="path to ai-spec-execution.md")
    parser.add_argument("--id", dest="only_id", help="report on a single item id, verbosely")
    parser.add_argument("--phase", help="report only ids starting P<phase>. (e.g. P0)")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    args = parser.parse_args(argv)

    if not args.spec.is_file():
        print(f"check_spec_status: {args.spec} does not exist; pass --spec to override", file=sys.stderr)
        return 2

    text = args.spec.read_text(encoding="utf-8")
    items, warnings = parse_items(text)
    if not items:
        print("check_spec_status: parsed zero P<phase>.<n> items; the spec's table shape may have changed", file=sys.stderr)
        return 2

    facts = gather_tree_facts()
    statuses = {item_id: evaluate_item(rows, facts) for item_id, rows in items.items()}

    try:
        selected = _select_ids(statuses, args.phase, args.only_id)
    except KeyError:
        print(f"check_spec_status: no item {args.only_id!r} in {args.spec}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(_json_payload(args.spec, items, warnings, statuses, selected), indent=2))
        return 0

    _print_report(statuses, selected, verbose=args.only_id is not None)
    if not (args.only_id or args.phase):
        _print_summary(items, warnings, statuses)
    return 0


if __name__ == "__main__":
    sys.exit(main())
