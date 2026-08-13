"""Build API pages from source signatures and docstrings."""

from __future__ import annotations

import ast
import html
import io
import textwrap
import tokenize
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ModuleSpec:
    name: str
    source: str


MODULES = (
    ModuleSpec("petta.atoms", "python/petta/atoms.py"),
    ModuleSpec("petta.space", "python/petta/space.py"),
    ModuleSpec("petta.ops", "python/petta/ops.py"),
    ModuleSpec("petta.convert", "python/petta/convert.py"),
    ModuleSpec("petta.matching", "python/petta/matching.py"),
    ModuleSpec("petta.measure", "python/petta/measure.py"),
    ModuleSpec("petta_soft", "petta_soft/petta_soft/__init__.py"),
    ModuleSpec("petta.subscribe", "python/petta/subscribe.py"),
    ModuleSpec("petta.foreign", "python/petta/foreign.py"),
    ModuleSpec("petta.integrate", "python/petta/integrate.py"),
    ModuleSpec("petta.arrays", "python/petta/arrays.py"),
    ModuleSpec("petta.results", "python/petta/results.py"),
)

DEFINITION_TYPES = (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)
REPO = Path(__file__).resolve().parents[2]
OUTPUT = REPO / "website" / "reference"


def blockquote(text: str) -> str:
    escaped = html.escape(text, quote=False)
    return "\n".join(">" if not line else f"> {line}" for line in escaped.splitlines())


def source_header(node: ast.AST, lines: list[str]) -> str:
    start = node.lineno - 1
    stop = node.end_lineno
    fragment = "".join(lines[start:stop])
    depth = 0
    for token in tokenize.generate_tokens(io.StringIO(fragment).readline):
        if token.type != tokenize.OP:
            continue
        if token.string in "([{":
            depth += 1
        elif token.string in ")]}":
            depth -= 1
        elif token.string == ":" and depth == 0:
            fragment_lines = fragment.splitlines(keepends=True)
            row, column = token.end
            header = "".join(fragment_lines[: row - 1]) + fragment_lines[row - 1][:column]
            return textwrap.dedent(header).rstrip()
    raise ValueError(f"definition on line {node.lineno} has no header colon")


def public_definitions(tree: ast.Module) -> list[ast.AST]:
    return [
        node
        for node in tree.body
        if isinstance(node, DEFINITION_TYPES) and not node.name.startswith("_")
    ]


def render_definition(node: ast.AST, lines: list[str], *, level: int = 2, owner: str = "") -> str:
    name = f"{owner}.{node.name}" if owner else node.name
    parts = [f"{'#' * level} `{name}`", "", "```python", source_header(node, lines), "```", ""]
    doc = ast.get_docstring(node, clean=True)
    parts.extend([blockquote(doc) if doc else "No docstring is defined.", ""])
    if isinstance(node, ast.ClassDef):
        for child in node.body:
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)) and not child.name.startswith("_"):
                parts.extend(render_definition(child, lines, level=level + 1, owner=node.name).splitlines())
                parts.append("")
    return "\n".join(parts).rstrip()


def render_module(spec: ModuleSpec) -> str:
    path = REPO / spec.source
    source = path.read_text(encoding="utf8")
    lines = source.splitlines(keepends=True)
    tree = ast.parse(source, filename=str(path))
    module_doc = ast.get_docstring(tree, clean=True)
    parts = [
        f"# `{spec.name}`",
        "",
        f"Source: `{spec.source}`.",
        "",
        blockquote(module_doc) if module_doc else "No module docstring is defined.",
        "",
        "The entries below reproduce the source signatures and docstrings.",
        "",
    ]
    definitions = public_definitions(tree)
    if definitions:
        for node in definitions:
            parts.extend([render_definition(node, lines), ""])
    elif spec.name == "pettorch.knn":
        parts.extend(
            [
                "## Re-exported class",
                "",
                "`EmbeddingStore` is documented under [`petta.arrays`](./petta-arrays#embeddingstore).",
                "",
            ]
        )
    else:
        parts.extend(["The module defines no public functions or classes.", ""])
    return "\n".join(parts).rstrip() + "\n"


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for spec in MODULES:
        target = OUTPUT / f"{spec.name.replace('.', '-')}.md"
        target.write_text(render_module(spec), encoding="utf8")


if __name__ == "__main__":
    main()
