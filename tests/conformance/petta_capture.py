"""Purpose: vendor upstream PeTTa's example corpus and freeze the answers it
    prints, so tests/conformance/petta.py gates against an oracle THIS
    repository owns rather than against whatever a sibling checkout happens to
    contain today. Record mode; petta.py is verify mode.

    Upstream's specification is executable: `test.sh` runs each
    `examples/*.metta`, greps stdout for `is ... should ...` lines, fails on a
    `❌` and requires a `✅`. The corpus IS the spec, so it is copied here byte
    for byte and its stdout captured beside it, the way TC39's test262 is
    vendored by the engines that must satisfy it.

Assumes:
  - an upstream PeTTa checkout is given with --upstream; its git HEAD is
    recorded in MANIFEST.json and a dirty worktree is refused, because a pin
    taken from uncommitted files names a state nobody can return to.
  - both engines accept the `silent` flag, so the captured bytes are the
    program's own answers rather than translator banners
    [source: upstream src/main.pl:3-13, engine/main.pl:54-57].
Guarantees:
  - every captured file is reproducible from the recorded commit: rerunning
    this against the same commit rewrites identical bytes, or the run is
    reported as nondeterministic and the file is ruled out of the corpus.
  - a skip carries its reason in the manifest, never a bare name.
Fails when:
  - asked to capture from a dirty or unresolvable checkout.
  - upstream itself prints a ❌ for a file: the oracle must be green before it
    can be an oracle, so that file is reported and left out.
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
PIN = HERE / "petta"
CORPUS = PIN / "examples"
LIBDIR = PIN / "lib"
EXPECTED = PIN / "expected"
MANIFEST = PIN / "MANIFEST.json"

ANSI = re.compile(r"\x1b\[[0-9;]*m")

# Not part of the corpus, with the reason each is out. The first three upstream
# skips itself in test.sh; greedy_chess and repl need a terminal, and under a
# runner greedy_chess does not terminate at all, printing ~18M lines because
# readln!/1 answers end_of_file forever once stdin is at EOF; the git ones
# clone over the network, which an offline gate cannot do.
SKIPS = {
    "repl.metta": "needs an interactive terminal",
    "llm_cities.metta": "needs a network and an API key",
    "torch.metta": "needs torch installed",
    "torch_lib.metta": "needs torch installed",
    "greedy_chess.metta": "needs a terminal: its command loop never ends at EOF",
    "git_import.metta": "clones from the network",
    "git_import2.metta": "clones from the network",
}


def run(main_pl: Path, cwd: Path, rel: str, timeout: int) -> tuple[int | None, str, bool]:
    """One engine run. start_new_session so a timeout kills swipl rather than
    orphaning it behind the shell, the shape
    extensions/python/tests/repository/test_example_parity.py already uses."""
    proc = subprocess.Popen(
        ["swipl", "--stack_limit=8g", "-q", "-s", str(main_pl), "--", rel, "silent"],
        cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
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


def upstream_commit(upstream: Path) -> str:
    dirty = subprocess.run(["git", "-C", str(upstream), "status", "--porcelain"],
                           capture_output=True, text=True, check=True).stdout
    tracked = [ln for ln in dirty.splitlines() if not ln.startswith("??")]
    if tracked:
        sys.exit(f"petta_capture: {upstream} has uncommitted changes; a pin taken "
                 f"from them names a state nobody can return to:\n" + "\n".join(tracked))
    return subprocess.run(["git", "-C", str(upstream), "rev-parse", "HEAD"],
                          capture_output=True, text=True, check=True).stdout.strip()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--upstream", required=True, type=Path,
                    help="a clean upstream PeTTa checkout to capture from")
    ap.add_argument("--timeout", type=int, default=90)
    ap.add_argument("--jobs", type=int, default=4)
    args = ap.parse_args()

    upstream = args.upstream.resolve()
    main_pl = upstream / "src" / "main.pl"
    if not main_pl.exists():
        sys.exit(f"petta_capture: {main_pl} does not exist")
    commit = upstream_commit(upstream)

    names = sorted(p.name for p in (upstream / "examples").glob("*.metta")
                   if p.name not in SKIPS)
    print(f"capturing {len(names)} examples from {upstream} @ {commit[:8]}", flush=True)

    def capture(name: str) -> dict:
        rel = f"examples/{name}"
        rc, out, timed = run(main_pl, upstream, rel, args.timeout)
        rc2, out2, timed2 = run(main_pl, upstream, rel, args.timeout)
        return {"name": name, "rc": rc, "out": out, "timeout": timed,
                "stable": (rc, out, timed) == (rc2, out2, timed2)}

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(capture, names))

    # The corpus keeps upstream's examples/ + lib/ SIBLING layout, because 41 of
    # these examples import by relative path (`../lib/lib_he`), which resolves
    # against the importing FILE's directory. `(library X)` is the other form
    # and resolves against the ENGINE's own directory (engine/metta.pl:373), so
    # that half still reaches this tree's libraries: path imports name the same
    # bytes on both sides, library imports name each engine's own, and that is
    # exactly the as-shipped comparison this lane wants.
    CORPUS.mkdir(parents=True, exist_ok=True)
    EXPECTED.mkdir(parents=True, exist_ok=True)
    LIBDIR.mkdir(parents=True, exist_ok=True)
    for stale in (list(CORPUS.glob("*")) + list(EXPECTED.glob("*.out"))
                  + list(LIBDIR.glob("*"))):
        if stale.is_file():
            stale.unlink()
    for support in (upstream / "lib").iterdir():
        if support.is_file():
            (LIBDIR / support.name).write_bytes(support.read_bytes())
    # Two examples import a sibling that is not a .metta file.
    for support in ("prologimport_example.pl", "python_import_file.py"):
        src = upstream / "examples" / support
        if src.exists():
            (CORPUS / support).write_bytes(src.read_bytes())

    entries, excluded = {}, {}
    for r in results:
        if r["timeout"]:
            excluded[r["name"]] = "upstream itself did not finish within the timeout"
        elif not r["stable"]:
            excluded[r["name"]] = "upstream's own output is not reproducible run to run"
        elif "❌" in r["out"]:
            excluded[r["name"]] = "upstream itself fails this example, so it cannot be an oracle"
        else:
            (CORPUS / r["name"]).write_bytes((upstream / "examples" / r["name"]).read_bytes())
            (EXPECTED / f"{r['name']}.out").write_text(r["out"])
            entries[r["name"]] = {"rc": r["rc"], "status": "conforms"}

    MANIFEST.write_text(json.dumps({
        "upstream": "https://github.com/trueagi-io/PeTTa.git",
        "commit": commit,
        "captured_with": "tests/conformance/petta_capture.py",
        "engine_flag": "silent",
        "skips": SKIPS,
        "excluded": excluded,
        "entries": entries,
    }, indent=1, sort_keys=True) + "\n")

    print(f"corpus  : {len(entries)} files")
    print(f"excluded: {len(excluded)}")
    for name, why in sorted(excluded.items()):
        print(f"    {name}: {why}")
    print(f"skipped : {len(SKIPS)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
