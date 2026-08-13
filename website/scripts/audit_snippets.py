"""Purpose: verify that tutorial code fences are exact excerpts from approved
sources, including Python examples nested under topical folders.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import re
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
SITE = REPO / "website"
SOURCE_PATHS = [
    REPO / "README.md",
    REPO / "python" / "examples" / "README.md",
    *(REPO / "python" / "examples").rglob("*.py"),
    *(REPO / "python" / "petta").glob("*.py"),
    *(REPO / "python" / "tests").glob("*.py"),
    REPO / "lib" / "lib_measure.metta",
    REPO / "lib" / "lib_soft.metta",
]
FENCE = re.compile(r"^```[^\n]*\n(.*?)^```\s*$", re.MULTILINE | re.DOTALL)


def main() -> None:
    sources = {path: path.read_text(encoding="utf8") for path in SOURCE_PATHS}
    failures: list[str] = []
    checked = 0
    for page in sorted(SITE.rglob("*.md")):
        relative = page.relative_to(SITE)
        if "node_modules" in relative.parts or ".vitepress" in relative.parts:
            continue
        if page.parent.name == "reference":
            continue
        text = page.read_text(encoding="utf8")
        for index, match in enumerate(FENCE.finditer(text), start=1):
            snippet = match.group(1).rstrip("\n")
            checked += 1
            if not any(snippet in source for source in sources.values()):
                failures.append(f"{relative} fence {index}")
    if failures:
        raise SystemExit("snippets not found in approved sources:\n" + "\n".join(failures))
    print(f"verified {checked} tutorial code fences against approved sources")


if __name__ == "__main__":
    main()
