"""Purpose: check this engine against upstream PeTTa, which is the arbiter.
    tests/conformance/petta/ holds upstream's example corpus and the exact
    stdout upstream printed for each file, captured by petta_capture.py from a
    named commit. This replays every entry through THIS engine and diffs, which
    is the difference between "PeTTa is the oracle" as a habit and as a check.

    Verify mode; petta_capture.py is record mode. The pin lives in this
    repository rather than in a sibling checkout, so CI gates on it and a
    neighbouring working tree cannot move a lane under it.

Assumes:
  - the pin was captured with the engines' shared `silent` flag, so the bytes
    compared are the program's own answers and not translator banners.
  - the corpus keeps upstream's examples/ + lib/ sibling layout, because its
    relative-path imports (`../lib/lib_he`) resolve against the importing
    file's directory while `(library X)` resolves against the engine's own
    (engine/metta.pl:373). Both halves are deliberate: a path import names the
    same bytes on both sides, a library import names each engine's own.
Guarantees:
  - SWI variable identifiers ($_12345) expose allocation history rather than
    meaning, so a mismatch is re-compared after first-occurrence alpha
    renaming and reported as renamed-only when that is all it was, the
    technique tests/upstream_bench.sh already uses.
  - a file whose status is `diverges` carries the difference it is ALLOWED to
    have, so it cannot drift further without failing: a recorded divergence is
    a ruling, not an exemption.
  - a run that raises or times out is reported as such rather than counted as
    agreeing.
Fails when:
  - --gate is passed and any `conforms` entry differs, or any `diverges` entry
    stops differing in exactly the recorded way. Without --gate this is a
    REPORT surface: it prints and exits 0.
  - the pin is absent: that is a configuration error and says so, rather than
    passing an empty corpus quietly.
Decides:
  - the unit of promotion is the FILE, not a percentage and not an area. An
    entry gates as soon as it agrees, so the burn-down's finish line is real
    and per-file.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import argparse
import json
import os
import re
import signal
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
#The pin directory, overridable so the gate itself can be tested. A gate that
#cannot be pointed at a planted disagreement is a wall nobody has watched fail
#[tested: test_the_conformance_gate_tells_the_three_cases_apart].
PIN = Path(os.environ.get("PETTA_PIN", HERE / "petta"))
CORPUS = PIN / "examples"
EXPECTED = PIN / "expected"
MANIFEST = PIN / "MANIFEST.json"

ANSI = re.compile(r"\x1b\[[0-9;]*m")
VARID = re.compile(r"\$_\d+")


def alpha(text: str) -> str:
    """First-occurrence renaming of SWI variable identifiers."""
    seen: dict[str, str] = {}
    def rename(match: re.Match) -> str:
        ident = match.group(0)
        if ident not in seen:
            seen[ident] = f"$_V{len(seen) + 1}"
        return seen[ident]
    return VARID.sub(rename, text)


def run_ours(name: str, timeout: int) -> tuple[int | None, str, bool]:
    proc = subprocess.Popen(
        # The `extensions` seat, because upstream loads janus unconditionally
        # and the pin was captured from an engine that had it. Without the
        # seat every python-touching entry differs on this side alone
        # [measured 2026-08-30: python.metta and python_import.metta].
        ["swipl", "--stack_limit=8g", "-q", "-s", str(ROOT / "engine" / "main.pl"),
         "--", f"examples/{name}", "silent", "extensions"],
        cwd=PIN, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, start_new_session=True,
    )
    try:
        out, err = proc.communicate(timeout=timeout)
        timed = False
    except subprocess.TimeoutExpired:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        out, err = proc.communicate()
        timed = True
    return proc.returncode, ANSI.sub("", (out or "") + (err or "")), timed


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--gate", action="store_true",
                    help="exit nonzero when a conforming entry differs")
    ap.add_argument("--record-divergences", action="store_true",
                    help="rule every entry that differs RIGHT NOW as `diverges`, "
                         "storing the output it gives, so the gate blocks a NEW "
                         "difference and any drift in a recorded one while the "
                         "known backlog burns down. Run it deliberately, never "
                         "to make a red lane green.")
    ap.add_argument("--timeout", type=int, default=90)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--show", type=int, default=8,
                    help="how many differing entries to print in full")
    args = ap.parse_args()

    if not MANIFEST.exists():
        print(f"petta: no pin at {MANIFEST.relative_to(ROOT)}. Capture one with\n"
              f"  python tests/conformance/petta_capture.py --upstream <checkout>",
              file=sys.stderr)
        return 2
    manifest = json.loads(MANIFEST.read_text())
    entries = manifest["entries"]

    def check(item: tuple[str, dict]) -> dict:
        name, ruling = item
        want = (EXPECTED / f"{name}.out").read_text()
        rc, got, timed = run_ours(name, args.timeout)
        return {"name": name, "status": ruling["status"], "want_rc": ruling["rc"],
                "rc": rc, "timeout": timed, "want": want, "got": got,
                "equal": got == want, "alpha_equal": alpha(got) == alpha(want),
                "recorded": ruling.get("ours")}

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(check, sorted(entries.items())))

    agree, blocking, ruled = [], [], []
    for r in results:
        if r["status"] == "conforms":
            (agree if r["alpha_equal"] and r["rc"] == r["want_rc"] else blocking).append(r)
        else:
            # A recorded divergence must still differ in exactly the way the
            # ruling says, or the ruling is stale and the run must say so.
            if r["recorded"] is not None and alpha(r["got"]) != alpha(r["recorded"]):
                blocking.append(r)
            else:
                ruled.append(r)

    total = len(results)
    print(f"== PeTTa conformance, upstream {manifest['commit'][:8]}")
    print(f"agreeing        : {len(agree)}/{total}")
    print(f"recorded rulings: {len(ruled)}")
    print(f"blocking        : {len(blocking)}")
    for r in blocking[: args.show]:
        print(f"\n--- {r['name']}  (status {r['status']}, "
              f"exit {r['want_rc']} -> {r['rc']}"
              f"{', TIMED OUT' if r['timeout'] else ''})")
        want, got = r["want"].splitlines(), r["got"].splitlines()
        for i in range(max(len(want), len(got))):
            a = want[i] if i < len(want) else "<no line>"
            b = got[i] if i < len(got) else "<no line>"
            if a != b:
                print(f"    upstream: {a[:110]}")
                print(f"    ours    : {b[:110]}")
                break
    if len(blocking) > args.show:
        print(f"\n... and {len(blocking) - args.show} more")

    if args.record_divergences:
        for r in results:
            entry = entries[r["name"]]
            if r["alpha_equal"] and r["rc"] == r["want_rc"]:
                entry["status"] = "conforms"
                entry.pop("ours", None)
            else:
                entry["status"] = "diverges"
                entry["ours"] = r["got"]
                entry["ours_rc"] = r["rc"]
        manifest["entries"] = entries
        MANIFEST.write_text(json.dumps(manifest, indent=1, sort_keys=True) + "\n")
        ruled = sum(1 for e in entries.values() if e["status"] == "diverges")
        print(f"\nrecorded: {len(entries) - ruled} conform, {ruled} ruled `diverges`")
        return 0

    if args.gate and blocking:
        print(f"\npetta: {len(blocking)} entries block the gate", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
