"""Purpose: verify tutorial fences against approved sources and report the
fixed P0.26 burn-down inventory.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SITE = REPO / "website"
BACKLOG = Path(__file__).with_name("snippet_backlog.tsv")
BASELINE_SIZE = 72
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
SHA256 = re.compile(r"[0-9a-f]{64}")


@dataclass(frozen=True)
class BacklogEntry:
    state: str
    page: str
    fence: int
    digest: str
    reason: str


@dataclass(frozen=True)
class Finding:
    page: str
    fence: int
    digest: str


def _backlog() -> dict[tuple[str, str], BacklogEntry]:
    if not BACKLOG.is_file():
        raise SystemExit(f"snippet backlog missing: {BACKLOG.relative_to(REPO)}")
    entries: dict[tuple[str, str], BacklogEntry] = {}
    for line_number, line in enumerate(BACKLOG.read_text(encoding="utf8").splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t", 4)
        if len(fields) != 5:
            raise SystemExit(f"{BACKLOG}:{line_number}: expected five tab-separated fields")
        state, page, fence_text, digest, reason = fields
        if state not in {"OPEN", "RESOLVED"}:
            raise SystemExit(f"{BACKLOG}:{line_number}: unknown state {state!r}")
        if not fence_text.isdecimal() or not SHA256.fullmatch(digest) or not reason:
            raise SystemExit(f"{BACKLOG}:{line_number}: invalid fence, digest, or reason")
        entry = BacklogEntry(state, page, int(fence_text), digest, reason)
        key = (page, digest)
        if key in entries:
            raise SystemExit(f"{BACKLOG}:{line_number}: duplicate backlog entry")
        entries[key] = entry
    if len(entries) != BASELINE_SIZE:
        raise SystemExit(
            f"{BACKLOG}: expected the fixed {BASELINE_SIZE}-entry baseline, "
            f"found {len(entries)}"
        )
    return entries


def _findings() -> tuple[int, list[Finding]]:
    missing = [path for path in SOURCE_PATHS if not path.is_file()]
    if missing:
        names = ", ".join(str(path.relative_to(REPO)) for path in missing)
        raise SystemExit(f"approved snippet source missing: {names}")
    sources = [path.read_text(encoding="utf8") for path in SOURCE_PATHS]
    failures: list[Finding] = []
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
            if not any(snippet in source for source in sources):
                failures.append(
                    Finding(
                        str(relative),
                        index,
                        hashlib.sha256(snippet.encode()).hexdigest(),
                    )
                )
    return checked, failures


def main() -> None:
    backlog = _backlog()
    checked, failures = _findings()
    remaining: list[tuple[Finding, BacklogEntry]] = []
    untracked: list[Finding] = []
    reopened: list[tuple[Finding, BacklogEntry]] = []
    current_keys = {(finding.page, finding.digest) for finding in failures}
    for finding in failures:
        entry = backlog.get((finding.page, finding.digest))
        if entry is None:
            untracked.append(finding)
        elif entry.state == "OPEN":
            remaining.append((finding, entry))
        else:
            reopened.append((finding, entry))

    stale = [
        entry
        for key, entry in backlog.items()
        if entry.state == "OPEN" and key not in current_keys
    ]
    backlog_path = BACKLOG.relative_to(REPO)
    print(
        f"snippet provenance backlog: {len(remaining)} of {BASELINE_SIZE} remain; "
        f"tracked in {backlog_path}"
    )
    for finding, entry in remaining:
        print(f"{finding.page} fence {finding.fence}: {entry.reason}")
    for finding in untracked:
        print(f"UNTRACKED {finding.page} fence {finding.fence}: no baseline entry")
    for finding, entry in reopened:
        print(f"REOPENED {finding.page} fence {finding.fence}: {entry.reason}")
    for entry in stale:
        print(f"RESOLVED SINCE INVENTORY {entry.page} fence {entry.fence}: {entry.reason}")

    if remaining or untracked or reopened:
        raise SystemExit(1)
    print(f"verified {checked} tutorial code fences against approved sources")


if __name__ == "__main__":
    main()
