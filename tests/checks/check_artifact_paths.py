"""Purpose: refuse a file-relative path expression that no longer resolves.

`b54dea73` renamed the chapter-19 C artifacts on 2026-08-27 and left three
consumers holding the old directory. Each was found separately, months apart, by
somebody noticing a test skip: `test_benchmarks.py` and
`benchmarks/configuration.py` under finding 26, and
`tests/.../test_c_handle_crossing.py` under finding 35, which survived the
repair of the other two because nothing asked the question in general. A path
that stopped resolving turns a guard into a permanent skip, and a permanent skip
reports success.

Grepping for the literal cannot do this. `examples/integration/c_extension` was
renamed while `extensions/python/examples/integration/` still exists, so the
same word is stale in one place and current in seven others. So each expression
is EVALUATED instead: `ast` folds `Path(__file__).resolve().parents[N] / "a" /
"b"` into a real path and the path is asked whether it exists.

A path that is CREATED at runtime rather than read has not stopped resolving and
is not a finding. It says so in place, on the same line or the one above:

    fixture = Path(__file__).resolve().parents[2] / "out" / "built.so"  # artifact-path-created

The door is deliberate. A wall with no door gets the lane disabled the first
time somebody writes an output path; a door that has to name itself keeps the
next stale constant visible.

Assumes: a checkout of this repository, and Python's own `ast`.
Guarantees:
  - a file-relative path expression naming something that does not exist fails
    the run, with the file, the line, and the path it folded to
    [tested: tests/checks/check_artifact_paths_selftest.py; commit=WORKTREE]
  - an expression marked `artifact-path-created` is not a finding, so a runtime
    output path does not have to disable the lane
    [tested: tests/checks/check_artifact_paths_selftest.py; commit=WORKTREE]
Fails when: an expression's segments are not literals, which it skips rather
  than guessing; a computed path is outside what this can decide.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import ast
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OPT_OUT = "artifact-path-created"
SKIP_PARTS = ("/ai-tmp/", "/.claude/", "/node_modules/", "/build/", "/.git/")


def folded(node: ast.BinOp, source: Path) -> Path | None:
    """Fold a `parents[N] / "a" / "b"` chain into the path it names, or None."""
    parts: list[str] = []
    current: ast.expr = node
    while isinstance(current, ast.BinOp) and isinstance(current.op, ast.Div):
        right = current.right
        if not (isinstance(right, ast.Constant) and isinstance(right.value, str)):
            return None
        parts.append(right.value)
        current = current.left
    if not (isinstance(current, ast.Subscript) and isinstance(current.slice, ast.Constant)):
        return None
    text = ast.unparse(current)
    if "__file__" not in text or "parents" not in text:
        return None
    base = source.resolve()
    for _ in range(current.slice.value + 1):
        base = base.parent
    for segment in reversed(parts):
        base = base / segment
    return base


def findings(root: Path) -> list[str]:
    """Every folded path that does not exist and did not opt out."""
    out: list[str] = []
    for source in sorted(root.rglob("*.py")):
        # Relative to the root, so a checkout that itself sits under one of
        # these names does not skip its whole tree. The selftest's fixture
        # lives in ai-tmp/ and caught exactly that.
        relative = f"/{source.relative_to(root)}"
        if any(part in relative for part in SKIP_PARTS):
            continue
        try:
            text = source.read_text(encoding="utf-8")
            tree = ast.parse(text)
        except (OSError, SyntaxError, UnicodeDecodeError):
            continue
        lines = text.splitlines()
        seen: set[int] = set()
        for node in ast.walk(tree):
            if not (isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div)):
                continue
            if node.lineno in seen:
                continue
            path = folded(node, source)
            if path is None or path.exists():
                continue
            window = "\n".join(lines[max(0, node.lineno - 2) : node.end_lineno])
            if OPT_OUT in window:
                continue
            seen.add(node.lineno)
            name = source.relative_to(root)
            out.append(f"{name}:{node.lineno}: path does not resolve: {path}")
    return out


def main() -> int:
    """Report every stale file-relative path expression."""
    problems = findings(ROOT)
    for problem in problems:
        print(f"  {problem}")
    print(f"artifact-paths: {len(problems)} finding(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
