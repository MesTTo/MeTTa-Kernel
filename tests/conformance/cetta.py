"""Purpose: replay the conformance corpus's CeTTa-routable fragment through
the fork's C core and gate that the SHARED fragment stays shared. CeTTa is
triangulation, never authority: LeaTTa defines, and agreement here is
regression detection on the fragment both runtimes serve, priced for the
day forms route to the C core in-process.

The checkout resolves through the CETTA_PATH environment override with the
sibling checkout as the default, the same env-override oracle pattern
tests/conformance/leatta.py carries and the workspace-path scanner excepts.

Assumes:
  - the fork's binary takes `--lang he --profile he-compat <file>` and
    prints one bracketed answer group per runnable form, `[]` included
    [measured 2026-08-20: the catalogue's 204 lane-runs, and the he lane's
    elided [] is exactly why the compat profile is the lane pinned here]
  - CeTTa stops a file after a top-level Error and exits 0, so fewer
    observed groups than expected under exit 0 is a truncation to surface,
    never a tail to forgive (fence F12 made loud)
Guarantees:
  - a fenced file is skipped with its fence printed, never silently
    [tested test_the_two_runtime_differential_corpus_gates_the_shared_fragment]
  - a shared-fragment file that stops agreeing fails the lane; a divergence
    outside the fragment is reported and never blocks
  - with the checkout or binary absent this reports that and exits 0, the
    leatta lane's absence policy
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import leatta  # noqa: E402  -- the corpus reader and canonical comparison

DEFAULT_CHECKOUT = Path(__file__).resolve().parents[2].parent / "CeTTa"
FENCES = Path(__file__).resolve().parent / "cetta_fences.txt"
FRAGMENT = Path(__file__).resolve().parent / "cetta_shared_fragment.txt"

#: The harness normalisations fences F13 and F12 price: a live pointer in
#: every space rendering, and variable epochs the C runtime appends.
ADDRESS = re.compile(r"0x[0-9a-f]+")
EPOCH = re.compile(r"\$([A-Za-z_][A-Za-z0-9_-]*)#\d+")


def checkout() -> Path:
    return Path(os.environ.get("CETTA_PATH", str(DEFAULT_CHECKOUT)))


def read_fences(path: Path) -> dict[str, list[str]]:
    """Shorthand -> fence ids. `types-basic/44` names the 44_* file of that
    area; a word shorthand names the file exactly."""
    fences: dict[str, list[str]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        fence, entry = line.split(None, 1)
        fences.setdefault(entry.strip(), []).append(fence)
    return fences


def fenced_as(relative: Path, fences: dict[str, list[str]]) -> list[str]:
    area = relative.parent.name
    base = relative.stem
    hits: list[str] = []
    for entry, ids in fences.items():
        entry_area, _, tail = entry.partition("/")
        if entry_area != area:
            continue
        if base == tail or base.startswith(f"{tail}_") or base.startswith(f"{tail}-"):
            hits.extend(ids)
    return sorted(set(hits))


def observe(binary: Path, path: Path, timeout: float) -> tuple[list[str], int, str | None]:
    """One file through the compat lane: its answer groups, how many lines
    were printed output rather than groups, and a harness error if any."""
    try:
        finished = subprocess.run(
            [str(binary), "--lang", "he", "--profile", "he-compat", str(path)],
            capture_output=True, text=True, timeout=timeout,
            cwd=binary.parent,
        )
    except subprocess.TimeoutExpired:
        return [], 0, f"timed out after {timeout:g}s"
    groups: list[str] = []
    printed = 0
    for line in finished.stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            stripped = ADDRESS.sub("0xADDR", stripped)
            stripped = EPOCH.sub(r"$\1", stripped)
            groups.append(leatta.canonical(stripped))
        elif stripped:
            printed += 1
    if finished.returncode != 0:
        return groups, printed, f"exit {finished.returncode}"
    return groups, printed, None


def compare(binary: Path, path: Path, timeout: float) -> leatta.Comparison:
    source = path.read_text(errors="replace")
    expected, skipped = leatta.expected_groups(source)
    #The corpus's MEASURED blocks carry the arbiter's own variable epochs
    #($x#0), so the epoch normalisation applies to BOTH sides: the sealed
    #file is recorded as agreeing, and comparing spellings the two writers
    #never shared would invent a divergence out of notation.
    expected = [EPOCH.sub(r"$\1", group) for group in expected]
    observed, _printed, error = observe(binary, path, timeout)
    if error is None and len(observed) < len(expected):
        error = (
            f"stopped after {len(observed)} of {len(expected)} groups under "
            f"exit 0: the CLI's silent stop after a top-level Error (F12)"
        )
    return leatta.Comparison(
        path=path,
        expected=expected,
        observed=observed,
        skipped=skipped,
        error=error,
        status=leatta.declared_status(source),
    )


def read_fragment(path: Path) -> list[str]:
    if not path.exists():
        return []
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=25.0)
    parser.add_argument("--show", type=int, default=12)
    parser.add_argument("--corpus", type=Path, default=leatta.CORPUS)
    parser.add_argument("--fragment-file", type=Path, default=FRAGMENT)
    parser.add_argument("--fences-file", type=Path, default=FENCES)
    parser.add_argument("--seed-fragment", action="store_true",
                        help="rewrite the shared-fragment pin from what agrees now")
    arguments = parser.parse_args(argv)
    corpus = arguments.corpus

    root = checkout()
    binary = root / "cetta"
    if not binary.is_file() or not os.access(binary, os.X_OK):
        print(
            f"cetta is not built at {binary} (set CETTA_PATH to the fork "
            f"checkout); the two-runtime differential is not checked here"
        )
        return 0
    if not corpus.is_dir():
        print(
            f"the conformance corpus is not checked out at {corpus}; "
            f"the two-runtime differential is not checked here"
        )
        return 0

    fences = read_fences(arguments.fences_file)
    fragment = set(read_fragment(arguments.fragment_file))

    fenced: list[tuple[str, list[str]]] = []
    results: list[leatta.Comparison] = []
    for path in sorted(corpus.rglob("*.metta")):
        relative = path.relative_to(corpus)
        ids = fenced_as(relative, fences)
        if ids:
            fenced.append((str(relative), ids))
            continue
        comparison = compare(binary, path, arguments.timeout)
        if comparison.comparable:
            results.append(comparison)

    agreeing = sorted(
        str(item.path.relative_to(corpus))
        for item in results
        if item.agrees
    )
    diverging = [item for item in results if not item.agrees]

    print(
        f"cetta lane: {len(results)} comparable files ran, "
        f"{len(agreeing)} agree, {len(diverging)} diverge, "
        f"{len(fenced)} fenced (F-classes skip the route, never silently)"
    )
    for name, ids in fenced[: arguments.show]:
        print(f"  fenced {','.join(ids)}: {name}")
    for item in diverging[: arguments.show]:
        relative = item.path.relative_to(corpus)
        print(f"  diverges: {relative}: {item.first_difference[:160]}")

    if arguments.seed_fragment:
        arguments.fragment_file.write_text(
            "# The shared fragment: corpus files whose he-compat lane agrees\n"
            "# with the corpus's own MEASURED expectations. A file leaving\n"
            "# this list fails the cetta lane; alignment work on the fork\n"
            "# grows it. Reseed with --seed-fragment after a fix lands.\n"
            + "\n".join(agreeing)
            + "\n",
            encoding="utf-8",
        )
        print(f"seeded {arguments.fragment_file.name} with {len(agreeing)} files")
        return 0

    missing = sorted(fragment - {p for p, _ in fenced} - set(agreeing))
    broken = [name for name in missing if name in {
        str(item.path.relative_to(corpus)) for item in results
    }]
    vanished = [name for name in missing if name not in broken]
    if broken:
        print(f"{len(broken)} shared-fragment file(s) stopped agreeing:")
        for name in broken[: arguments.show]:
            print(f"  {name}")
        return 1
    if vanished:
        print(
            f"{len(vanished)} shared-fragment file(s) are gone or fenced; "
            f"reseed the pin deliberately:"
        )
        for name in vanished[: arguments.show]:
            print(f"  {name}")
        return 1
    print(f"shared fragment holds: {len(fragment)} pinned files all agree")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
