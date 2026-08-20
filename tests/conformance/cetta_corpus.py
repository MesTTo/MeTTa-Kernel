"""Purpose: the forward half of the two-runtime differential. The fork
pins this engine's whole example corpus as oracles (one manifest entry per
example, streams normalized and sha-pinned), and this lane replays every
entry through the CURRENT tree and compares against the pin, so an engine
change that moves an example's answers fails HERE with the entry named,
and the remedy is a deliberate re-freeze in the fork, codec-doc's
regenerate discipline across two repositories.

The capture and the normalization are the fork's own: the generator
module is imported from the checkout and its run_oracle drives run.sh
exactly as the freeze did, so there is no second copy of the
normalization contract to drift. The manifest pins the generator's own
sha, and a mismatch between the pinned sha and the imported file is a
loud refusal rather than a comparison under a different contract.

Assumes:
  - the fork checkout resolves through CETTA_PATH with the sibling as the
    default, the same env-override oracle pattern leatta.py carries
Guarantees:
  - with the checkout absent this reports that and exits 0
    [tested test_the_forward_corpus_lane_verifies_the_repinned_manifest]
  - a tampered or drifted oracle fails with the entry named
    [tested test_the_forward_corpus_lane_verifies_the_repinned_manifest]
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

DEFAULT_CHECKOUT = Path("/home/user/Dev/CeTTa")
REPO = Path(__file__).resolve().parents[2]


def checkout() -> Path:
    return Path(os.environ.get("CETTA_PATH", str(DEFAULT_CHECKOUT)))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--petta-dir", type=Path, default=REPO)
    parser.add_argument("--manifest", type=Path, default=None)
    parser.add_argument("--show", type=int, default=10)
    parser.add_argument("--timeout-scale", type=float, default=1.0)
    arguments = parser.parse_args(argv)

    root = checkout()
    generator_path = root / "scripts" / "petta_corpus_manifest.py"
    manifest_path = (
        arguments.manifest
        if arguments.manifest is not None
        else root / "tests" / "petta" / "corpus" / "manifest.json"
    )
    if not generator_path.is_file() or not manifest_path.is_file():
        print(
            f"the fork's corpus machinery is not checked out at {root} "
            f"(set CETTA_PATH); the forward differential is not checked here"
        )
        return 0

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    pinned_generator = manifest.get("generator_sha256")
    actual_generator = hashlib.sha256(generator_path.read_bytes()).hexdigest()
    if pinned_generator != actual_generator:
        print(
            "the manifest pins a different generator than the checkout "
            "holds, so a comparison would run under an unpinned "
            "normalization contract: re-freeze the corpus in the fork"
        )
        return 1

    sys.path.insert(0, str(generator_path.parent))
    try:
        import petta_corpus_manifest as generator
    finally:
        sys.path.pop(0)

    if manifest.get("normalization") != generator.normalization_contract():
        print("the manifest's normalization contract is not the generator's")
        return 1

    petta_dir = arguments.petta_dir.resolve()
    mismatches: list[str] = []
    entries = manifest["entries"]
    for entry in entries:
        name = entry["name"]
        oracle = entry["oracle"]
        timeout = entry["timeout_seconds"] * arguments.timeout_scale
        exit_code, stdout, stderr = generator.run_oracle(
            petta_dir, name, timeout
        )
        if exit_code != oracle["exit"]:
            mismatches.append(
                f"{name}: exit {exit_code}, pinned {oracle['exit']}"
            )
        elif stdout != oracle["stdout"]:
            mismatches.append(f"{name}: stdout moved off its pin")
        elif stderr != oracle["stderr"]:
            mismatches.append(f"{name}: stderr moved off its pin")

    print(
        f"forward corpus lane: {len(entries)} pinned entries replayed "
        f"against {petta_dir.name}, {len(entries) - len(mismatches)} match, "
        f"{len(mismatches)} moved"
    )
    for line in mismatches[: arguments.show]:
        print(f"  {line}")
    if mismatches:
        print(
            "an entry off its pin means this tree changed what an example "
            "answers: if the change is deliberate, re-freeze the corpus in "
            "the fork with the cause recorded; if not, it is a regression"
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
