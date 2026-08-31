"""Purpose: resolve every in-progress commit placeholder to a real object ID.

The placeholder in an evidence tag becomes the object ID of the commit whose
tree supplied that evidence, and it is rewritten only where the file's own
grammar says the text is a comment.

A commit cannot contain its own object ID, so the scheme writes the functional
state as commit A, then replaces the placeholder with A's ID in a
provenance-only commit B. Doing that replacement by hand is a plain textual
substitution over the whole tree, and on 2026-08-31 one reached into twelve
STRING LITERALS: the re-pin tool's own tag template began writing a stale
object ID into every twin it priced, and the evidence gate's self-test planted
an object ID where the gate was still testing for the word, so the RELEASE=1
rule went untested and passed. Nothing said so, because a resolvable ID is
exactly what the gate wants to see.

The fix is that this pass exists, and that it decides per file class rather
than per byte:

  .py           a placeholder inside a string literal that is not a docstring
                belongs to code that EMITS or MATCHES pins, and is left alone.
                The distinction is `ast`'s, not a regex's.
  .pl .plt      a placeholder is a pin when a `%` opens a comment before it on
                its line, which is where all 218 of this tree's Prolog pins sit.
  .sh           the same rule with `#`.
  .ts .c .h     the same rule with `//`, plus `/* ... */` blocks. The C seat
                writes its whole contract in one leading `/* ... */`, so the
                block half is not a fallback there but the usual case.
  .json         commentless, so the measurement prose is the only place a pin
                can be, and every placeholder in one is a pin. This is the rule
                check_evidence_tags.provenance_sites already applies to them.

Anything else is REFUSED by name rather than guessed at, and every occurrence
the pass declines is printed with its reason, so a file class that starts
carrying pins is visible the first time rather than silently skipped.

Assumes: it is run from a checkout of this repository, with git on PATH.
Guarantees:
  - a placeholder in a comment, a docstring or a JSON measurement is rewritten,
    and one in a non-docstring string literal or a backticked mention is not
    [tested: tests/checks/check_pin_provenance_selftest.py]
  - the scan covers exactly the files check_evidence_tags reads, because it
    imports that module's own globs rather than restating them
    [tested: tests/checks/check_pin_provenance_selftest.py]
  - --check writes nothing and exits 1 when any pin would be rewritten, which
    is the same condition RELEASE=1 refuses on
    [tested: tests/checks/check_pin_provenance_selftest.py]
  - a commit that does not resolve is refused before any file is opened
    [tested: tests/checks/check_pin_provenance_selftest.py]
Fails when: a pin sits somewhere the file's grammar cannot distinguish from
  code. It is reported, not rewritten, and finishing it is a human's call.
Owns resources: none; it rewrites files in place and holds nothing open.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import argparse
import ast
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_evidence_tags import (  # noqa: E402  -- HERE must be on the path first
    PLACEHOLDER,
    PROVENANCE_SOURCES,
    ROOT,
    SOURCES,
)

TOKEN = re.compile(rf"\bcommit={re.escape(PLACEHOLDER)}\b")
BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)


def _docstring_spans(text: str) -> list[tuple[int, int]]:
    """Byte spans of every string constant that is NOT a docstring.

    Inverted deliberately: the caller wants to know where NOT to write, and a
    docstring is the one string a Python file uses to speak about itself. The
    walk covers f-strings too, whose literal halves are Constant nodes under a
    JoinedStr and carry the same hazard: the gate's own refusal message is an
    f-string, and the hand sweep rewrote it.
    """
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return []
    documented: set[int] = set()
    for node in ast.walk(tree):
        body = getattr(node, "body", None)
        if not isinstance(node, ast.Module | ast.ClassDef | ast.FunctionDef | ast.AsyncFunctionDef):
            continue
        if (
            body
            and isinstance(body[0], ast.Expr)
            and isinstance(body[0].value, ast.Constant)
            and isinstance(body[0].value.value, str)
        ):
            documented.add(id(body[0].value))
    lines = text.splitlines(keepends=True)
    starts = [0]
    for line in lines:
        starts.append(starts[-1] + len(line))

    def offset(row: int, column: int) -> int:
        return starts[row - 1] + column

    spans = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Constant) or not isinstance(node.value, str):
            continue
        if id(node) in documented or node.end_lineno is None or node.end_col_offset is None:
            continue
        spans.append((offset(node.lineno, node.col_offset), offset(node.end_lineno, node.end_col_offset)))
    return spans


def _backticked(text: str, at: int) -> bool:
    """Whether the placeholder at `at` sits inside a backtick span on its line.

    `commit=WORKTREE` in backticks is the word being DISCUSSED. Three of the
    twelve sites the hand sweep damaged were exactly that: prose in a docstring
    and in a corpus README explaining what the re-pin tool writes.
    """
    start = text.rfind("\n", 0, at) + 1
    end = text.find("\n", at)
    line = text[start : end if end != -1 else len(text)]
    return line.count("`", 0, at - start) % 2 == 1


def sites(path: Path, text: str) -> list[tuple[int, int, str | None]]:
    """Every placeholder in one file as (offset, line, reason it is declined)."""
    suffix = path.suffix
    found = []
    if suffix == ".py":
        skip = _docstring_spans(text)
    elif suffix in (".ts", ".c", ".h"):
        skip = [match.span() for match in BLOCK_COMMENT.finditer(text)]
    else:
        skip = []
    for match in TOKEN.finditer(text):
        at = match.start()
        line = text.count("\n", 0, at) + 1
        reason: str | None = None
        if _backticked(text, at):
            reason = "a backticked mention of the placeholder, not a pin"
        elif suffix == ".py":
            if any(low <= at < high for low, high in skip):
                reason = "a string literal that is not a docstring: this code emits or matches pins"
        elif suffix in (".pl", ".plt", ".sh"):
            marker = "%" if suffix != ".sh" else "#"
            head = text[text.rfind("\n", 0, at) + 1 : at]
            if marker not in head:
                reason = f"no {marker} opens a comment before it on its line"
        elif suffix in (".ts", ".c", ".h"):
            head = text[text.rfind("\n", 0, at) + 1 : at]
            if "//" not in head and not any(low <= at < high for low, high in skip):
                reason = "neither // nor a /* */ block opens a comment around it"
        elif suffix != ".json":
            reason = f"{suffix} has no comment rule here; add one rather than guessing"
        found.append((at, line, reason))
    return found


def scan() -> list[tuple[Path, list[tuple[int, int, str | None]], str]]:
    """Every file the evidence gate reads that holds a placeholder."""
    seen: set[Path] = set()
    out = []
    for glob in (*SOURCES, *PROVENANCE_SOURCES):
        for path in sorted(ROOT.glob(glob)):
            if path in seen:
                continue
            seen.add(path)
            text = path.read_text(encoding="utf-8")
            if PLACEHOLDER not in text:
                continue
            found = sites(path, text)
            if found:
                out.append((path, found, text))
    return out


def resolve(commit: str) -> str:
    """The full object ID of a commit, or a refusal naming what was asked."""
    done = subprocess.run(
        ["git", "rev-parse", "--verify", "--end-of-options", f"{commit}^{{commit}}"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if done.returncode != 0:
        msg = f"pin_provenance: {commit} does not resolve to a commit in {ROOT}"
        raise SystemExit(msg)
    return done.stdout.strip()


def main(argv: list[str] | None = None) -> int:
    """Resolve the placeholders, or report the ones still open under --check."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--commit",
        default="HEAD",
        help="the commit whose tree supplied the evidence; its full object ID replaces the placeholder",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="write nothing and exit 1 if any placeholder would be rewritten",
    )
    arguments = parser.parse_args(argv)

    found = scan()
    pins = [(path, [item for item in items if item[2] is None], text) for path, items, text in found]
    declined = [
        (path, line, reason) for path, items, _ in found for _, line, reason in items if reason
    ]
    total = sum(len(items) for _, items, _ in pins)

    if arguments.check:
        for path, items, _ in pins:
            for _, line, _reason in items:
                print(f"{path.relative_to(ROOT)}:{line}: placeholder awaiting a provenance pin")
    else:
        oid = resolve(arguments.commit)
        for path, items, text in pins:
            if not items:
                continue
            rewritten = text
            for at, _line, _reason in reversed(items):
                rewritten = rewritten[:at] + f"commit={oid}" + rewritten[at + len(f"commit={PLACEHOLDER}") :]
            path.write_text(rewritten, encoding="utf-8")
            print(f"{path.relative_to(ROOT)}: {len(items)} pin(s) -> {oid}")

    for path, line, reason in declined:
        print(f"{path.relative_to(ROOT)}:{line}: left alone, {reason}")
    print(
        f"{total} pin(s) {'awaiting' if arguments.check else 'resolved'}, "
        f"{len(declined)} occurrence(s) left alone, over "
        f"{len(found)} file(s) carrying the placeholder"
    )
    return 1 if arguments.check and total else 0


if __name__ == "__main__":
    sys.exit(main())
