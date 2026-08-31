"""Purpose: prove pin_provenance.py tells a pin from the code that writes one.

It plants one of every shape in a tree and runs the real pass over it.

Running the pass on THIS repository proves the repository is clean. It says
nothing about whether the pass can tell a pin from a string literal, which is
the whole of its job and the exact distinction a hand sweep got wrong on
2026-08-31: twelve string literals were rewritten, the re-pin tool began
writing a stale object ID into every twin it priced, and the evidence gate's
own RELEASE=1 rule stopped being tested because its self-test planted an
object ID where the gate tested for the word.

Every planted citation is built from variables rather than written out, the
same discipline check_evidence_selftest.py keeps: a literal one in this file is
a claim about THIS repository as far as the evidence gate is concerned, and
these fixtures are deliberately unbacked.

Assumes: git on PATH, and a writable temporary directory.
Guarantees:
  - each of the seven planted shapes lands on the side the pass documents, and
    the pass reports the declined ones with a reason
    [tested: tests/checks/check_pin_provenance_selftest.py]
  - a placeholder outside the evidence gate's own globs is neither rewritten
    nor reported, so the pass and the gate cover the same files
    [tested: tests/checks/check_pin_provenance_selftest.py]
  - --check exits 1 while pins remain and 0 once they are resolved, and a
    commit that does not resolve is refused before any file changes
    [tested: tests/checks/check_pin_provenance_selftest.py]
Fails when: run against a tree it did not write. It asserts on a fixture it
  generates and nothing else.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_evidence_tags import PLACEHOLDER  # noqa: E402  -- HERE must be on the path first

WORD = f"commit={PLACEHOLDER}"
TAG = "tested"
WHEN = "2026-08-31"

# (path, text, lines that must be rewritten, lines that must be declined)
PLANTS = (
    (
        "engine/plant.pl",
        [
            "% Purpose: a fixture.",
            f"%   - a Prolog pin [{TAG} {WHEN}: a_plunit_test; {WORD}].",
            f"an_atom('{WORD}').",
        ],
        [2],
        [3],
    ),
    (
        "extensions/python/tools/plant.py",
        [
            '"""A fixture.',
            "",
            f"A docstring pin [{TAG} {WHEN}: test_collected; {WORD}].",
            f"The word itself, discussed rather than pinned: `{WORD}`.",
            '"""',
            "",
            f"#: A comment pin [{TAG} {WHEN}: test_collected; {WORD}].",
            f'TEMPLATE = "[{{kind}} {{date}}: emitted; {WORD}]"',
        ],
        [3, 7],
        [4, 8],
    ),
    (
        "extensions/node/src/plant.ts",
        [
            f"// A TypeScript pin [{TAG} {WHEN}: a case; {WORD}].",
            f"/* A block pin [{TAG} {WHEN}: a case; {WORD}]. */",
            f'export const emitted = "{WORD}";',
        ],
        [1, 2],
        [3],
    ),
    (
        "engine/plant.sh",
        [
            "# Purpose: a fixture runner.",
            f"# Guarantees: it runs [{TAG} {WHEN}: a case; {WORD}].",
            f'echo "{WORD}"',
        ],
        [2],
        [3],
    ),
    (
        "extensions/cmetta/plant.h",
        [
            "/* Purpose: a fixture header.",
            f" * Guarantees: the block half [{TAG} {WHEN}: a case; {WORD}].",
            " */",
            f'static const char *emitted = "{WORD}";',
            f"// The line half [{TAG} {WHEN}: a case; {WORD}].",
        ],
        [2, 5],
        [4],
    ),
    (
        "engine/plant.json",
        [
            "{",
            f'  "measures": "a commentless baseline [{TAG} {WHEN}: a case; {WORD}]."',
            "}",
        ],
        [2],
        [],
    ),
    # Outside every glob check_evidence_tags reads, so the pass must not see it.
    (
        "extensions/python/tests/plant.py",
        [f"#: An unscanned pin [{TAG} {WHEN}: test_collected; {WORD}]."],
        [],
        [],
    ),
)


def build(root: Path) -> str:
    """The fixture tree, committed, with the pass beside its imports."""
    tools = root / "tools/checks"
    tools.mkdir(parents=True)
    for module in ("check_evidence_tags.py", "evidence_runners.py", "pin_provenance.py"):
        shutil.copy(HERE / module, tools / module)
    (root / "check.sh").write_text("# a gate script the runner model expects\n")
    # engine/*.sh is one of the pass's globs, so the shell plant below is only
    # reached when the fixture writes it before the loop that writes the rest.
    for name, lines, _rewritten, _declined in PLANTS:
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(lines) + "\n")
    for command in (
        ["git", "init", "-q"],
        ["git", "add", "-A"],
        ["git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "fixture"],
    ):
        subprocess.run(command, cwd=root, check=True, capture_output=True)
    return subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True
    ).stdout.strip()


def run(root: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    """The real pass, run over the fixture tree with the given arguments."""
    return subprocess.run(
        [sys.executable, str(root / "tools/checks/pin_provenance.py"), *arguments],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )


def complaints() -> list[str]:
    """Everything the pass got wrong on a tree whose right answers are known."""
    found: list[str] = []
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        live = build(root)

        # A commit that names nothing is refused before a file is opened.
        missing = run(root, "--commit", "0" * 40)
        if missing.returncode == 0:
            found.append("a commit that does not resolve was accepted")
        if any((root / name).read_text().count(WORD) != sum(1 for line in lines if WORD in line)
               for name, lines, _r, _d in PLANTS):
            found.append("a refused commit still rewrote a file")

        checked = run(root, "--check")
        if checked.returncode != 1:
            found.append(f"--check exited {checked.returncode} with pins outstanding, wanted 1")
        found.extend(
            f"--check did not name {name}:{line}, which is a pin"
            for name, _lines, rewritten, _declined in PLANTS
            for line in rewritten
            if f"{name}:{line}: placeholder awaiting" not in checked.stdout
        )
        found.extend(
            f"--check named {name}:{line} a pin, which is code"
            for name, _lines, _rewritten, declined in PLANTS
            for line in declined
            if f"{name}:{line}: placeholder awaiting" in checked.stdout
        )

        resolved = run(root, "--commit", live)
        if resolved.returncode != 0:
            found.append(f"the pass exited {resolved.returncode}: {resolved.stderr.strip()}")
        for name, lines, rewritten, declined in PLANTS:
            text = (root / name).read_text().splitlines()
            found.extend(
                f"{name}:{line} was not rewritten: {text[line - 1].strip()!r}"
                for line in rewritten
                if f"commit={live}" not in text[line - 1]
            )
            for line in declined:
                if WORD not in text[line - 1]:
                    found.append(f"{name}:{line} was rewritten and should not have been: "
                                 f"{text[line - 1].strip()!r}")
                if f"{name}:{line}: left alone" not in resolved.stdout:
                    found.append(f"{name}:{line} was left alone without saying why")
            if not rewritten and not declined and len(lines) == 1:
                if WORD not in text[0]:
                    found.append(f"{name} is outside the gate's globs and was rewritten anyway")
                if name in resolved.stdout:
                    found.append(f"{name} is outside the gate's globs and was reported anyway")

        again = run(root, "--check")
        if again.returncode != 0:
            found.append(f"--check exited {again.returncode} on a resolved tree, wanted 0")
    return found


def main() -> int:
    """Report the defects and exit nonzero if there are any."""
    found = complaints()
    for one in found:
        print(one)
    planted = sum(len(rewritten) + len(declined) for _n, _l, rewritten, declined in PLANTS)
    print(
        f"pin-provenance selftest: {len(found)} defect(s), over {planted} planted placeholders "
        f"in {len(PLANTS)} files, one of them outside the gate's globs"
    )
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
