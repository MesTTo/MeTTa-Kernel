"""Purpose: say which files this repository's runners execute, and in which
tier, so a tested claim can be checked against the gate rather than against
the tree alone.

check_evidence_tags.py used to ask only whether a cited name existed. A name
can exist in a file nothing runs, which is how engine/translator.pl came to cite
a tests/performance/reduce_dispatch.pl for its operator-table guarantee: the
file was real, and no runner ever opened it. This lane is what found it, and
the citation names a plunit unit now.

Two ways of learning what a runner executes, because neither covers the other:

  literally    a path written into a runner is executed by it. check.sh names
               tests/prolog/static_checks.pl and extensions/python/tools/reference.py this
               way, and reading the paths out needs no model of anything.
  by glob      pytest, the plunit loop and test.sh each select a whole tree.
               Nothing in the text names the files, so each of the three is
               DECLARED below with the verbatim runner line it models. If that
               line moves, the anchor stops matching and this reports it,
               rather than quietly modelling a runner that no longer exists.

check.sh's own GATE and REPORT tiers are read off its `run` lines, because a
REPORT failure is forgiven and cannot back a claim. The two workflow files are
runners too, and untiered here: ci.yml runs three shell suites that check.sh
does not, and a claim resting on one of them is backed, just not by the local
gate.
Assumes:
  - `:- initialization(main, main)` exits 1 when main fails, so a Prolog script
    named by a runner reports its failure [measured 2026-08-18: swipl 10 exits
    1 on `main :- fail.` and 0 on `main :- true.`]
  - extensions/python/pyproject.toml leaves pytest's discovery at its documented defaults,
    which PYTEST_DISCOVERY_KEYS re-checks on every run
    [source: https://docs.pytest.org/en/stable/explanation/goodpractices.html]
Guarantees:
  - a file no runner reaches is absent from executed(), and a file only a
    REPORT lane reaches carries tier REPORT
    [tested 2026-08-18: tests/checks/check_evidence_selftest.py]
  - a declared collector whose anchor has left its runner is reported instead
    of being applied [tested 2026-08-18: tests/checks/check_evidence_selftest.py]
Fails when:
  - a Prolog file is handed to swipl by a Python script rather than by a
    runner or by another Prolog file's consult. tests/conformance/leatta_run.pl
    is the one case, and it reads as unexecuted here. Python path strings are
    not followed on purpose: reference.py names the pages it REWRITES, and
    reading those as executions would be worse than the gap.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import fnmatch
import re
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def _component_runners() -> tuple[str, ...]:
    """Every component's own check.sh, discovered the way check.sh sources them.

    A component's lanes moved out of the root gate into its own directory, and
    this list was four hardcoded names. A lane the evidence model cannot see is
    a lane whose paths look unrun, so a claim citing a file only that lane runs
    reads as unbacked. Measured 2026-08-28: discovery restores exactly one file
    to the executed model, extensions/node/test/atom.test.ts, and no tag cites it
    today -- so the exposure is latent rather than realised, and this exists to
    keep it that way as component lanes grow, not to repair a live break.
    """
    found = []
    for pattern in ("engine/check.sh", "extensions/*/check.sh"):
        found += [str(p.relative_to(ROOT)) for p in sorted(ROOT.glob(pattern))]
    return tuple(found)


# Every script that runs part of this repository. check.sh is the gate; test.sh
# is reached from it and owns the example corpus; the two workflows run check.sh
# and, in ci.yml's case, three shell suites it does not; and each component's
# own check.sh, which the gate SOURCES so its lanes share one summary.
RUNNERS = (
    "check.sh",
    "test.sh",
    ".github/workflows/checks.yml",
    ".github/workflows/ci.yml",
) + _component_runners()

# `run TIER NAME COMMAND...`, check.sh's own lane declaration, and the shell
# functions those lanes call. A lane's text is the command plus the body of
# every function it reaches, so a path written inside check_prolog_static
# belongs to the GATE lane that calls it.
LANE = re.compile(r"^run\s+(GATE|REPORT)\s+(\S+)\s+(.*)$", re.M)
FUNCTION = re.compile(r"^([a-z_][a-z0-9_]*)\(\)\s*\{\n(.*?)^\}", re.M | re.S)
ONE_LINE_FUNCTION = re.compile(r"^([a-z_][a-z0-9_]*)\(\)\s*\{([^\n]*)\}[ \t]*$", re.M)

# A path written into a runner. Anchored on a suffix this repository executes,
# so `$SUMMARY` and `*.plt` are not mistaken for files.
PATHISH = re.compile(r"[$\w./{}-]*[\w}-]\.(?:py|pl|plt|sh|metta|ts)\b")
# A lane that runs a package's own npm script runs that package's tests, and
# the script NAME is the whole indirection: `npm run test` inside
# extensions/node runs every extensions/node/test/*.test.ts, and nothing in the
# lane's text is a path. Reading the indirection is what lets an evidence
# claim written in a TypeScript source name a test in one of them; without it
# those claims are unbacked because the checker cannot see the suite at all.
NPM_SCRIPT = re.compile(r"\bnpm\s+(?:run\s+(?:--silent\s+)?)?(?:test|typecheck|kit)\b")
CD = re.compile(r"\bcd\s+(?:--\s+)?[\"']?([$\w./-]+)")
# A path named to be LEFT OUT is not a path the runner executes. Reading these
# as executions marked examples/ch20-extending-the-engine/20-04-modules-and-the-catalog/_fixtures/imports/
# import_error_broken.metta as gated by the very lane that skips it.
EXCLUSION = re.compile(
    r"(?:!\s+-path|-not\s+-path|--ignore|--exclude|--extend-exclude)(?:=|\s+)\S+"
)
SHELL_VARIABLES = (
    ("$HERE/", ""),
    ("${HERE}/", ""),
    # check.sh sets PYDIR="$HERE/extensions/python". These read "python/",
    # the pre-partition location, so any lane naming $PYDIR/<file> resolved
    # to a path that is not in the tree and its file read as unexecuted.
    # No lane writes that shape today, which is why nothing was lost yet.
    ("$PYDIR/", "extensions/python/"),
    ("./", ""),
    ("$HERE", "."),
    ("$PYDIR", "extensions/python"),
)

# pytest's discovery is documented rather than configured here, so the model
# below is only right while extensions/python/pyproject.toml stays silent about it.
PYTEST_DISCOVERY_KEYS = ("python_files", "python_classes", "python_functions", "testpaths")

# A Prolog file a runner names pulls in whatever it loads, and those clauses
# are as much a part of the run as its own: static_checks.pl reaches its
# published-surface check through `:- ensure_loaded(surface_walk)`. A Python
# import is NOT the same thing and is deliberately not followed, because pytest
# collects a test by the file it is written in, not by what imports it.
PROLOG_LOAD = re.compile(r"\b(?:ensure_loaded|consult|use_module|include)\(\s*'?([^'\s,)]+)'?")
PROLOG_COMMENT = re.compile(r"'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"|%[^\n]*")


@dataclass(frozen=True)
class Execution:
    """How one file comes to be run."""

    tier: str
    runner: str


#: Where a runner starts the Prolog files under a directory, when that is not
#: the directory the file sits in. SWI resolves a LOAD-time relative path
#: against the file and a RUN-time one, an initialization goal or a consult in
#: a test body, against the WORKING DIRECTORY, so a suite two levels below its
#: runner's cwd writes both depths and only one of them is file-relative.
#: Following the file's directory alone lost fifteen files the moment the
#: suites were grouped: eight shipped libraries an
#: `initialization(consult('../../lib/...'))` pulls in, and the seven providers
#: a test body consults by bare name [measured 2026-08-27].
RUNNER_WORKING_DIRECTORY = {"tests/prolog": "tests/prolog"}


def prolog_loads(path: Path) -> list[Path]:
    """Every Prolog file this one loads, resolved the way SWI resolves it."""
    text = PROLOG_COMMENT.sub(
        lambda found: "" if found.group().startswith("%") else found.group(),
        path.read_text(encoding="utf-8", errors="replace"),
    )
    bases = [path.parent]
    relative = str(path.relative_to(ROOT)) if ROOT in path.parents else ""
    for prefix, working in RUNNER_WORKING_DIRECTORY.items():
        if relative.startswith(prefix + "/"):
            bases.append(ROOT / working)
    loaded = []
    for target in PROLOG_LOAD.findall(text):
        for base in bases:
            candidate = base / target
            if not candidate.suffix:
                candidate = candidate.with_suffix(".pl")
            if candidate.is_file():
                loaded.append(candidate.resolve())
                break
    return loaded


@dataclass(frozen=True)
class Collector:
    """A runner line that selects a whole tree, and what it selects.

    `anchor` is a verbatim fragment of the runner. It is checked before the
    collector is applied, so a moved or deleted runner line surfaces as a
    finding rather than as a model that has silently stopped matching.
    """

    runner: str
    tier: str
    lane: str
    anchor: str
    root: str
    patterns: tuple[str, ...]
    recursive: bool
    excludes: tuple[str, ...] = ()
    skip_file: str = ""
    skip_anchor: str = ""


COLLECTORS = (
    Collector(
        runner="check.sh",
        tier="GATE",
        lane="pytest",
        anchor="pytest tests -q -p no:benchmark",
        root="extensions/python/tests",
        patterns=("test_*.py", "*_test.py"),
        recursive=True,
    ),
    Collector(
        runner="check.sh",
        tier="GATE",
        lane="plunit",
        anchor="for suite in suites/*/*.plt",
        root="tests/prolog/suites",
        patterns=("*.plt",),
        recursive=True,
    ),
    # test.sh runs each example under run.sh and fails the lane on a nonzero
    # exit, which is what makes an example's own !(test ...) forms evidence.
    Collector(
        runner="test.sh",
        tier="GATE",
        lane="shell",
        anchor="find ./examples -type f -name '*.metta'",
        root="examples",
        patterns=("*.metta",),
        recursive=True,
        excludes=("*/_fixtures/*",),
        skip_file="tests/data/example_skips.txt",
        skip_anchor="grep -v '^#' tests/data/example_skips.txt | awk 'NF {print $1}'",
    ),
)


def _literal(token: str) -> str | None:
    """A runner token with its shell variables spent, or None if it still has one."""
    for name, replacement in SHELL_VARIABLES:
        token = token.replace(name, replacement)
    return None if "$" in token or "{" in token else token


def _lane_texts(runner: str, text: str) -> list[tuple[str, str, str]]:
    """(tier, lane, text) for each unit of work the runner declares."""
    functions = dict(FUNCTION.findall(text)) | dict(ONE_LINE_FUNCTION.findall(text))
    lanes = []
    for tier, name, command in LANE.findall(text):
        reached, seen, pending = command, set(), [command]
        while pending:
            current = pending.pop()
            for function, body in functions.items():
                if function in seen or not re.search(rf"\b{re.escape(function)}\b", current):
                    continue
                seen.add(function)
                reached += "\n" + body
                pending.append(body)
        lanes.append((tier, f"{runner}: {name}", reached))
    if not lanes:
        # test.sh and the workflows declare no tiers. Both are reached from a
        # GATE lane or run the gate themselves, so their work is gating.
        lanes.append(("GATE", runner, text))
    return lanes


def _skipped(collector: Collector, text: str) -> tuple[frozenset[str], list[str]]:
    """The paths the runner drops from its selection, read where the runner reads them."""
    if not collector.skip_file:
        return frozenset(), []
    listing = ROOT / collector.skip_file
    if collector.skip_anchor not in text or not listing.is_file():
        return frozenset(), [
            f"{collector.runner}: it no longer reads {collector.skip_file} the way "
            f"{collector.skip_anchor!r} did, so the {collector.lane} lane's corpus "
            f"cannot be modelled"
        ]
    return frozenset(
        line.split()[0]
        for line in listing.read_text().splitlines()
        if line.strip() and not line.startswith("#")
    ), []


def executed() -> tuple[dict[Path, Execution], list[str]]:
    """Every file a runner executes, and everything about that this cannot decide."""
    runs: dict[Path, Execution] = {}
    problems: list[str] = []
    texts = {}

    def record(path: Path, tier: str, runner: str) -> None:
        previous = runs.get(path)
        if previous is None or (previous.tier == "REPORT" and tier == "GATE"):
            runs[path] = Execution(tier, runner)

    for runner in RUNNERS:
        path = ROOT / runner
        if not path.is_file():
            problems.append(f"{runner}: absent, so what it runs cannot be modelled")
            continue
        texts[runner] = path.read_text()

    for runner, text in texts.items():
        for tier, lane, lane_text in _lane_texts(runner, text):
            lane_text = EXCLUSION.sub(" ", lane_text)
            # A bare `static_checks.pl` is a path relative to whatever the lane
            # last changed into, so every directory it enters is a candidate.
            directories = (ROOT,) + tuple(
                candidate
                for target in CD.findall(lane_text)
                if (spent := _literal(target)) is not None
                and (candidate := ROOT / spent).is_dir()
            )
            for token in PATHISH.findall(lane_text):
                spent = _literal(token)
                if spent is None:
                    continue
                for directory in directories:
                    if (candidate := directory / spent).is_file():
                        record(candidate.resolve(), tier, lane)
            if NPM_SCRIPT.search(lane_text):
                for directory in directories:
                    if not (directory / "package.json").is_file():
                        continue
                    for suite in sorted((directory / "test").glob("*.test.ts")):
                        record(suite.resolve(), tier, lane)
                        break

    for collector in COLLECTORS:
        text = texts.get(collector.runner)
        if text is None or collector.anchor not in text:
            problems.append(
                f"{collector.runner}: the {collector.lane} lane no longer contains "
                f"{collector.anchor!r}, so what it runs cannot be modelled"
            )
            continue
        skips, trouble = _skipped(collector, text)
        problems.extend(trouble)
        root = ROOT / collector.root
        for pattern in collector.patterns:
            for found in root.rglob(pattern) if collector.recursive else root.glob(pattern):
                relative = str(found.relative_to(ROOT))
                if relative in skips or found.is_symlink():
                    continue
                if any(fnmatch.fnmatch(relative, exclude) for exclude in collector.excludes):
                    continue
                record(found.resolve(), collector.tier, f"{collector.runner}: {collector.lane}")

    pending = [path for path in runs if path.suffix in (".pl", ".plt")]
    while pending:
        current = pending.pop()
        execution = runs[current]
        for loaded in prolog_loads(current):
            known = runs.get(loaded)
            if known is None or (known.tier == "REPORT" and execution.tier == "GATE"):
                record(loaded, execution.tier, execution.runner)
                pending.append(loaded)

    configuration = ROOT / "extensions/python/pyproject.toml"
    if not configuration.is_file():
        problems.append(
            "extensions/python/pyproject.toml is absent, so whether pytest still discovers by its "
            "documented defaults cannot be read"
        )
        return runs, problems
    section = configuration.read_text().partition("[tool.pytest.ini_options]")[2]
    for key in PYTEST_DISCOVERY_KEYS:
        if re.search(rf"^{key}\s*=", section.partition("\n[")[0], re.M):
            problems.append(
                f"extensions/python/pyproject.toml sets pytest's {key}, so the collectors above "
                f"model a discovery this project no longer uses"
            )
    return runs, problems
