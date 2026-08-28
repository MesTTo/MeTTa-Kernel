"""Purpose: check that the evidence tags in obligation headers are backed by
something. A tested claim asserts that running what it names demonstrates the
guarantee above it, and thirteen of them named tests that had never existed in
the tree's history, including all four cited by the engine pool's Guarantees
block. A claim with nothing behind it is indistinguishable from the many that
are real, which is what makes it corrosive rather than untidy.

Reads only. No engine, no imports from the package, so this runs on a tree
that does not boot and finishes in well under a second.

What each tag has to carry, and why only this much:

  tested    every name in it exists as a test, a plunit unit, a named check,
            a shell suite, an example, or a path in the tree; that target can
            report a failure; and a runner executes it
  measured  a YYYY-MM-DD date, so the claim can go stale
  source    a date or a reference

Existence alone was the whole check until 2026-08-18, and it is the weakest of
the three. engine/translator.pl cited a tests/performance/reduce_dispatch.pl for
its operator-table guarantee: the file was real, its only failure path was a
cross-run hash comparison that said nothing about operator tables, and no
runner had ever opened it. So a tested claim now has to survive three
questions, not one. That citation names translator_operator_dispatch now and
the eight scripts under tests/performance/ are gone, each one a measurement
that printed a number and asserted nothing.

Can it fail? Language by language, because the answer is written differently
in each:

  .plt, .pl   a plunit test/1,2 clause, or the `main` of a script started by
              `:- initialization(main, main)`, which SWI exits 1 for when main
              fails; or, for a file with neither, one that loads it and has
              one, which is how surface_walk.pl's checks run under
              static_checks.pl.
  .py         a `def test*` pytest will collect, or, for a gate script cited
              whole, an exit path that can be nonzero. NOT the presence of an
              `assert`: that rule is SonarSource's S2699 and its documented
              false positive is the test that proves a call does not raise
              [source: https://github.com/openrewrite/rewrite-testing-
              frameworks/issues/121]. Both of this tree's two cases are that
              one, test_strict_accepts_a_pruned_branch_and_every_reduction and
              test_optional_surfaces_load_only_when_requested, so the rule
              would have been wrong twice and right never.
  .metta      a (test ...), (test-no-answer ...) or (assert* ...) form, which
              test/3 throws metta_test_failed for [source: engine/metta.pl:2283].
  .sh         an exit path that can be nonzero.

Does anything run it? evidence_runners.py answers that from the runners
themselves. A file only check.sh's REPORT tier reaches is named as such, since
a forgiven failure cannot back a claim.

The measured and source rules stop at the date deliberately. In this tree the
NUMBER a measurement claims almost always sits in the sentence the tag stamps,
not inside the brackets, and reading it out of surrounding prose would flag
correct headers far more often than wrong ones. The date is the part that is
unambiguous, and ageing is what the tag is for.

`assumed` is unchecked on purpose. It is the honest tag for a claim nobody has
verified, and demanding evidence for it would push authors back to stating
unverified claims in the same voice as measured facts.
Assumes:
  - evidence_runners.executed reports REPORT for a file only a forgiven lane
    runs [tested 2026-08-18: tests/checks/check_evidence_selftest.py]
Guarantees:
  - a tested claim naming something absent fails the run, and a claim spanning
    several comment lines is read as one claim
    [tested 2026-08-18: tests/checks/check_evidence_selftest.py]
  - a tested claim naming a target that cannot fail, that no runner executes,
    or that only a REPORT lane runs, fails the run
    [tested 2026-08-18: tests/checks/check_evidence_selftest.py]
Fails when:
  - asked whether a target tests the PARTICULAR guarantee it is cited for.
    Every rule here is necessary and none is sufficient: a script that runs
    and can fail still proves nothing if its failure does not depend on the
    claim. reduce_dispatch.pl is exactly that shape and only the runner
    question caught it.
  - asked whether the PREDICATE a claim names is the one that runs. That is a
    reachability question and Prolog does not answer it to a reader: goals
    live in a test's options and in begin_tests', a multifile hook is called
    by the engine, and assertz installs clauses at run time. A call graph
    tried here rejected 25 predicates that are all called. The file is the
    unit, and SWI answers the finer question with prolog_walk_code/1 against a
    loaded database, which static_checks.pl already does.
  - reading a plunit test that does not start in column 1, or a Python name
    bound by anything but a def. Both are how this tree is written and neither
    is how Prolog or Python must be written.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import ast
import os
import re
import subprocess
import sys
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

from evidence_runners import ROOT, Execution, executed, gate_scripts, prolog_loads

SOURCES = (
    "engine/*.pl",
    "lib/*/*.pl",
    "lib/*/*.py",
    "extensions/python/metta/*.py",
    "extensions/python/metta/*.pl",
    "extensions/python/examples/*.py",
    "extensions/mork/mork_ffi/*.pl",
    "extensions/python/tools/*.py",
    "tests/checks/*.py",
    # The Node binding is TypeScript, and its sources make the same kind of
    # claim the Python ones do. Its Prolog half is here for the same reason
    # extensions/python/metta/*.pl is.
    "extensions/node/*.pl",
    "extensions/node/src/*.ts",
    "extensions/node/src/*/*.ts",
)

# Commentless formats, scanned for PROVENANCE ONLY. A JSON baseline is exempt
# from the obligation header, which is why it is not in SOURCES, but a
# commentless format is not exempt from pinning its evidence: leaving these out
# made the lane blind to a whole file type, and RELEASE=1 reported zero
# placeholders on 2026-08-26 while baseline.json held four and
# extension-baseline.json two, all of which survived the 305-tag sweep in
# c918e7fd for exactly that reason.
#
# Only the commit half of the contract applies. Their re-pin comments are long
# measurement prose written for a reader, and running the claim analysis over
# it reads ordinary sentences as tags: scanning baseline.json under SOURCES
# reported "tested: names goes", "names red", "names against" and "names read"
# from one row's narrative. The pin check is a regex over commit= and cannot
# make that mistake.
# Discovered rather than named, the way evidence_runners finds a component's
# scripts: a seat that grows its own benchmarks grows its own baseline, and a
# hardcoded list would leave that seat's commit pins unchecked in the same
# silence this lane exists to end.
PROVENANCE_SOURCES = ("extensions/*/benchmarks/*.json",)

# Where a name may be defined. metta/_compliance.py holds real tests, shipped
# for a provider author to inherit; they run here too, under each
# SpaceComplianceSuite subclass, which is why the package is walked at all.
PYTHON_TREES = ("extensions/python/tests", "extensions/python/benchmarks", "extensions/python/metta", "tests")

# The tag and everything up to its closing bracket, across newlines: a claim
# listing three tests wraps, and a per-line scan reads the first line as an
# unterminated claim and skips it silently, which is how a checker for missing
# evidence comes to miss the evidence that is missing. The tag must also be
# FOLLOWED by a separator and a body, or the same pattern matches an ordinary
# Prolog variable spelled [Source] and the checker reports the file it reads.
CLAIM = re.compile(
    r"\[(tested|measured|source)[:\s]([^\]]*)\]", re.IGNORECASE | re.DOTALL
)
# A `node --test` case names itself in prose: `it("...")` and `describe("...")`
# each register one, which is what an evidence claim in a TypeScript source
# points at.
NODE_TEST = re.compile(r"""^\s*(?:it|describe)\(\s*["'`]([^"'`]+)["'`]""", re.M)
# A name written in prose, quoted so the splitter takes it whole. It may WRAP,
# because a claim sits in a comment and a comment is wrapped like any other
# prose, so the match spans newlines and the name's whitespace is normalised
# to the single spaces the test's own title carries.
QUOTED_NAME = re.compile(r'"([^"]{4,}?)"', re.DOTALL)
COMMENT_PREFIX = re.compile(r"^[ \t]*[%#*]*[ \t]*", re.MULTILINE)
DATE = re.compile(r"\d{4}-\d{2}-\d{2}")
IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(?::[A-Za-z_][A-Za-z0-9_]*)*$")
REFERENCE = re.compile(r"https?://|\w+\.\w+:\d+|\w+/[\w./-]+")
SUFFIXES = (".py", ".pl", ".plt", ".metta", ".sh")

# `translator.plt:malformed_seam_is_refused` and
# `test_per_space.py::test_eval_uses_the_spaces_own_equations` name a file and
# a test inside it. Three claims are written this way and the identifier rule
# dropped all three without a word, which is a citation nobody checks.
QUALIFIED = re.compile(rf"^(\S+(?:{'|'.join(re.escape(s) for s in SUFFIXES)}))::?(\w+)$")

# Words that appear inside a claim's prose rather than naming anything.
PROSE = frozenset(
    """and or the a an in of with by at to for on end via plus then also
    through both all each every same test tests suite suites case cases
    e g eg ie i see also above below here there is are was were it its
    this that these those not no yes if when while as from into over
    under after before during than then rather instead but so because
    which what who whom whose how why where when whether""".split()
)

PROLOG_ENTRY = re.compile(r":-\s*initialization\(\s*(\w+)\s*,\s*main\s*\)")
# A plunit test clause starts in column 1, which is where SWI's own style puts
# every clause head. The looser `^\s*test\(` this replaced also matched the
# indented goal `test(1, 2, _)` in metta.plt and registered `1`, plus one
# `<unit>:1` per unit, as though they were tests.
PROLOG_TEST = re.compile(r"^test\(\s*(\w+)", re.M)
# A MeTTa form whose failure stops the file: test/3 throws metta_test_failed.
METTA_ASSERTION = re.compile(r"\((?:test|test-no-answer|assert[\w-]*)[\s(]")
SHELL_FAILURE = re.compile(r"\bexit\s+[1-9]|\breturn\s+[1-9]|\|\|\s*exit\b|^set -e", re.M)


@dataclass(frozen=True)
class Target:
    """One thing a claim can name, and the file whose execution backs it."""

    kind: str
    path: Path
    run_path: Path
    fails: str | None
    note: str = ""


@dataclass(frozen=True)
class Evidence:
    """What the tree offers a claim: names, the files behind them, and what runs."""

    targets: dict[str, list[Target]]
    runs: dict[Path, Execution]
    files: frozenset[str]
    reports: dict[Path, str]


def _text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def _python_files() -> list[Path]:
    return [path for tree in PYTHON_TREES for path in sorted((ROOT / tree).rglob("*.py"))]


def _unconditionally_skipped(node: ast.AST) -> bool:
    """`@pytest.mark.skip` with no condition. skipif is an environment, not a hole."""
    decorators = getattr(node, "decorator_list", [])
    return any(re.search(r"\bmark\.skip\b", ast.unparse(one)) for one in decorators)


def _scope_definitions(node: ast.AST) -> Iterator[ast.AST]:
    """Every def and class that lands in this scope's namespace.

    `if` and `try` included, because they do not open a scope. Three of this
    tree's property tests sit under a module-level `else:` that picks a
    hypothesis strategy, and pytest collects them like any other module
    attribute. Reading only Module.body lost all three.
    """
    for member in (
        getattr(node, "body", [])
        + getattr(node, "orelse", [])
        + getattr(node, "finalbody", [])
        + list(getattr(node, "handlers", []))
    ):
        if isinstance(member, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            yield member
        elif isinstance(member, (ast.If, ast.Try, ast.With, ast.For, ast.While, ast.ExceptHandler)):
            yield from _scope_definitions(member)


def _python_targets(runs: dict[Path, Execution]) -> dict[str, list[Target]]:
    """Every `def test*` pytest collects, and the file whose run reaches it.

    pytest collects a `test` prefixed function at module level, and one inside
    a `Test` prefixed class with no __init__; a class reached only through such
    a subclass is collected too, which is how the shipped compliance suites in
    metta/_compliance.py come to run [source:
    https://docs.pytest.org/en/stable/explanation/goodpractices.html].
    """
    trees: dict[Path, ast.Module] = {}
    for path in _python_files():
        try:
            trees[path] = ast.parse(_text(path))
        except SyntaxError:
            continue

    classes: dict[str, list[tuple[Path, ast.ClassDef]]] = {}
    for path, tree in trees.items():
        for node in ast.walk(tree):
            if isinstance(node, ast.ClassDef):
                classes.setdefault(node.name, []).append((path, node))

    # Which class bodies a collected test module drags in, and through which
    # file, since that file's execution is what backs a claim on an inherited
    # test.
    inherited: dict[int, Path] = {}

    def descend(node: ast.ClassDef, through: Path) -> None:
        for base in node.bases:
            name = ast.unparse(base).rsplit(".", maxsplit=1)[-1]
            for _, definition in classes.get(name, []):
                if id(definition) not in inherited:
                    inherited[id(definition)] = through
                    descend(definition, through)

    for path, tree in trees.items():
        if runs.get(path.resolve()) is None:
            continue
        for node in _scope_definitions(tree):
            if isinstance(node, ast.ClassDef) and node.name.startswith("Test"):
                inherited.setdefault(id(node), path)
                descend(node, path)

    targets: dict[str, list[Target]] = {}

    def collect(node: ast.AST, path: Path, run_path: Path | None, note: str) -> None:
        for member in _scope_definitions(node):
            if isinstance(member, ast.ClassDef) or not member.name.startswith("test"):
                continue
            fails = "pytest reports a failure"
            if run_path is None:
                fails, note = None, "pytest does not collect it"
            elif _unconditionally_skipped(member):
                fails, note = None, "it is skipped unconditionally"
            targets.setdefault(member.name, []).append(
                Target("pytest", path, run_path or path, fails, note)
            )

    for path, tree in trees.items():
        selected = runs.get(path.resolve()) is not None
        collect(tree, path, path if selected else None, "")
        for node in ast.walk(tree):
            if not isinstance(node, ast.ClassDef):
                continue
            through = inherited.get(id(node))
            initialised = any(
                isinstance(member, (ast.FunctionDef, ast.AsyncFunctionDef))
                and member.name == "__init__"
                for member in node.body
            )
            if through is None or initialised:
                collect(node, path, None, "")
            else:
                collect(node, path, through, f"through {node.name}")
    return targets


def _prolog_report(text: str) -> str:
    """How one Prolog file reports a failure, or "" when it cannot on its own."""
    if PROLOG_TEST.search(text):
        return "plunit reports a failing test"
    if PROLOG_ENTRY.search(text):
        return "the script exits 1 when its entry goal fails"
    return ""


def _prolog_reports() -> dict[Path, str]:
    """How each Prolog file under tests/ reports a failure, or "" when it cannot.

    A FILE property, not a per-predicate one. Whether a particular predicate is
    reached cannot be decided by reading the text: plunit runs goals written in
    a test's options and in begin_tests' options, a multifile hook is called by
    the engine and never by the file that defines it, and assertz installs
    clauses at run time. A call graph built here rejected 25 predicates that
    are all called, and each pattern it learned uncovered another. SWI answers
    this question with prolog_walk_code/1 against a loaded database, which is
    what tests/prolog/static_checks.pl already does and what a reader cannot.
    """
    reports = {
        path.resolve(): _prolog_report(_text(path))
        for path in sorted((ROOT / "tests").rglob("*.pl*"))
    }
    # A file with no entry of its own still runs, and still fails, when one
    # that has an entry loads it. static_checks.pl reaches its published
    # surface check through `:- ensure_loaded(surface_walk)`, and nine of
    # surface_walk.pl's predicates read as unbacked without this.
    settled = False
    while not settled:
        settled = True
        for path, why in list(reports.items()):
            if not why:
                continue
            for loaded in prolog_loads(path):
                if reports.get(loaded) == "":
                    reports[loaded] = f"{path.name} loads it and reports its failure"
                    settled = False
    return reports


def _prolog_targets(reports: dict[Path, str]) -> dict[str, list[Target]]:
    """plunit units and tests, and the named checks a Prolog script runs."""
    targets: dict[str, list[Target]] = {}
    for path in sorted((ROOT / "tests").rglob("*.pl*")):
        text = _text(path)
        run_path = path.resolve()
        why = reports[run_path]
        note = "" if why else "it has no plunit test, no entry goal, and nothing loads it"
        units = re.findall(r"begin_tests\(\s*(\w+)", text)
        named = [("plunit", unit) for unit in units]
        for name in PROLOG_TEST.findall(text):
            named += [("plunit", key) for key in [name, *(f"{u}:{name}" for u in units)]]
        # A check the gate runs as a script rather than as a plunit test is
        # evidence too: static_checks.pl is one, and its checks are named
        # predicates. A name worth registering carries arguments or a body.
        named += [("prolog", n) for n in re.findall(r"^([a-z]\w*)\s*(?::-|\()", text, re.M)]
        for kind, name in named:
            targets.setdefault(name, []).append(Target(kind, path, run_path, why or None, note))
    return targets


def _node_targets(runs: dict[Path, Execution]) -> dict[str, list[Target]]:
    """Every name a `node --test` suite declares: its describes and its its.

    A TypeScript suite names its cases in prose rather than in identifiers, so
    the name a claim points at is the STRING, and both `describe` and `it`
    register one. The file itself is a target too, which is what lets a claim
    name a whole suite the way one may name a Python test module.
    """
    targets: dict[str, list[Target]] = {}
    for path in sorted((ROOT / "extensions" / "node" / "test").glob("*.test.ts")):
        resolved = path.resolve()
        fails = "node --test reports a failure" if resolved in runs else None
        note = "" if fails else "no lane runs it"
        for name in NODE_TEST.findall(_text(path)):
            targets.setdefault(name, []).append(Target("node", path, resolved, fails, note))
        targets.setdefault(path.name, []).append(Target("node", path, resolved, fails, note))
    return targets


def gather() -> tuple[Evidence, list[str]]:
    """Every name a claim may legitimately point at, and what backs it."""
    runs, problems = executed()
    reports = _prolog_reports()
    targets = _python_targets(runs)
    for name, found in _prolog_targets(reports).items():
        targets.setdefault(name, []).extend(found)
    for name, found in _node_targets(runs).items():
        targets.setdefault(name, []).extend(found)
    for path in sorted((ROOT / "examples").rglob("*.metta")):
        targets.setdefault(path.stem, []).append(file_target(path, reports))
    for path in sorted((ROOT / "tests").rglob("*.sh")):
        targets.setdefault(path.stem, []).append(file_target(path, reports))
    files = {target.path.name for group in targets.values() for target in group}
    return Evidence(targets, runs, frozenset(files), reports), problems


def file_target(path: Path, reports: dict[Path, str]) -> Target:
    """What a claim naming a whole file gets: the file's own way of failing."""
    text = _text(path)
    resolved = path.resolve()
    if path.suffix == ".metta":
        if METTA_ASSERTION.search(text):
            return Target("example", path, resolved, "a test form throws when it does not match")
        return Target("example", path, resolved, None, "it holds no (test ...) or (assert ...) form")
    if path.suffix == ".sh":
        if SHELL_FAILURE.search(text):
            return Target("shell", path, resolved, "the suite exits nonzero")
        return Target("shell", path, resolved, None, "it never exits nonzero")
    if path.suffix in (".pl", ".plt"):
        why = reports.get(resolved, _prolog_report(text))
        return Target(
            "prolog", path, resolved, why or None,
            "it has no plunit test, no entry goal, and nothing loads it",
        )
    if path.suffix == ".ts":
        if NODE_TEST.search(text):
            return Target("node", path, resolved, "node --test reports a failure")
        return Target("node", path, resolved, None, "it declares no test")
    if path.suffix == ".py":
        if re.search(r"^\s*(?:async\s+)?def\s+test", text, re.M):
            return Target("python", path, resolved, "pytest reports a failure")
        if re.search(r"raise SystemExit|sys\.exit\((?!0\))", text):
            return Target("python", path, resolved, "the script exits nonzero")
        return Target("python", path, resolved, None, "it has no test and no nonzero exit")
    return Target(
        "file", path, resolved, None, f"nothing here reads a {path.suffix} file for one"
    )


def target_problem(token: str, target: Target, known: Evidence) -> str | None:
    """Why this target does not back a claim, or None when it does."""
    where = target.path.relative_to(ROOT)
    at = "" if str(where) == token else f" in {where}"
    if target.fails is None:
        return f"names {token}{at}, which cannot report a failure: {target.note}"
    execution = known.runs.get(target.run_path)
    if execution is None:
        run_where = target.run_path.relative_to(ROOT)
        through = "" if run_where == where else f", reached only through {run_where}"
        return f"names {token}{at}{through}, which no runner executes"
    if execution.tier != "GATE":
        return (
            f"names {token}{at}, which only {execution.runner} runs, "
            f"a REPORT lane whose failure is forgiven"
        )
    return None


def resolve(token: str, known: Evidence) -> list[Target] | str:
    """The targets a claim's token names, or why it names none."""
    qualified = QUALIFIED.match(token)
    if qualified is not None:
        where, name = qualified.groups()
        basename = Path(where).name
        found = [
            target
            for target in known.targets.get(name, [])
            if target.path.name == basename or target.path == ROOT / where
        ]
        if found:
            return found
        if basename in known.files or (ROOT / where).is_file():
            return f"names {name}, which is not in {where}"
        return f"names the path {where}, which is not in the tree"
    if "/" in token or token.endswith(SUFFIXES):
        path = ROOT / token
        if not path.is_file():
            return f"names the path {token}, which is not in the tree"
        return [file_target(path, known.reports)]
    if not IDENTIFIER.match(token):
        return []
    found = known.targets.get(token) or known.targets.get(token.split(":")[-1])
    return found or f"names {token}, which is not a test in the tree"


#: The obligation-header scheme documents a tested tag as carrying either a
#: test name or an exact gate command, and the gate command half is this. It is
#: the right evidence for a claim no single test can carry: the llms.txt
#: checker's claim is that every name, path and count in the file holds, and
#: what proves it is running the lane. Reading the command as a list of test
#: names reported `sh` and `llms` as missing tests, which is the checker
#: failing to know its own scheme.
GATE_COMMAND = re.compile(r"\b(?:GATE_ONLY=1\s+)?sh\s+check\.sh\s+([a-z0-9-]+)")

#: The other shape an exact gate command takes: an interpreter, the script it
#: runs, and that script's own flags, as in
#: `python extensions/python/tools/phrasebook.py --gate`. The lane above names a
#: LANE; this names the SCRIPT, and what makes it evidence is the same thing,
#: that a GATE lane runs it.
#:
#: Without this the body was split into words, and the leading interpreter was
#: read as a test NAME. Two such claims passed for as long as they had been
#: written because `python` happened to be the stem of a shipped example,
#: examples/integration/python.metta, so a phrasebook claim was backed by an
#: unrelated MeTTa program; renaming that file to carry its reading-order
#: number is what exposed it [measured 2026-08-27].
SCRIPT_COMMAND = re.compile(
    r"\b(?:python3?|swipl|node)\s+((?:[\w.-]+/)*[\w.-]+\.(?:py|pl|mjs|ts))\b"
)

#: How check.sh names a lane, so a command naming a lane that does not exist is
#: still a finding.
CHECK_LANE = re.compile(r"^run\s+(?:GATE|REPORT)\s+([a-z0-9-]+)", re.MULTILINE)


def gate_lanes() -> frozenset[str]:
    """Every lane name the gate runs, the root driver's and each component's.

    `sh check.sh <lane>` still names all of them, because the root driver
    SOURCES every component's check.sh and its `run` filters on the argument
    list, so a lane's file says nothing about whether the command works.
    Reading the root file alone said otherwise the moment a lane moved into a
    component, and it said it about a lane the gate runs [measured 2026-08-28:
    `sh check.sh mypy ty` in extensions/python/metta/_rules.py:13 read as
    naming a lane check.sh does not run, one commit after mypy moved into
    extensions/python/check.sh].
    """
    return frozenset(
        lane for script in gate_scripts() for lane in CHECK_LANE.findall(_text(script))
    )


def gate_command_problems(body: str, known: Evidence) -> list[str] | None:
    """None when the body is not a gate command; otherwise what is wrong with it."""
    match = GATE_COMMAND.search(body)
    if match is not None:
        lane = match.group(1)
        if lane in gate_lanes():
            return []
        return [f"names the check.sh lane {lane}, which the gate does not run"]
    match = SCRIPT_COMMAND.search(body)
    if match is None:
        return None
    where = match.group(1)
    found = resolve(where, known)
    if isinstance(found, str):
        return [found]
    verdicts = [target_problem(where, target, known) for target in found]
    return [verdicts[0]] if verdicts and all(verdicts) else []


def tested_problems(body: str, known: Evidence) -> list[str]:
    command = gate_command_problems(body, known)
    if command is not None:
        return command
    stripped = DATE.sub("", body)
    problems = []
    # A `node --test` case names itself in PROSE, so a claim that points at one
    # has to be able to quote it. The quoted segments are taken whole and
    # removed before the rest is split on whitespace, which is what keeps
    # "makes === structural" one name instead of three words that are none.
    quoted = [" ".join(found.split()) for found in QUOTED_NAME.findall(stripped)]
    for token in [*quoted, *re.split(r"[\s,;]+", QUOTED_NAME.sub(" ", stripped))]:
        token = token.strip(" :.'`()") if token in quoted else token.strip(" :.'\"`()")
        if not token or token.lower() in PROSE:
            continue
        found = resolve(token, known)
        if isinstance(found, str):
            problems.append(found)
            continue
        # A name can be defined more than once. One good definition backs the
        # claim, so only report when every one of them fails.
        verdicts = [target_problem(token, target, known) for target in found]
        if verdicts and all(verdicts):
            problems.append(verdicts[0])
    return problems


def measured_problems(body: str, known: Evidence) -> list[str]:
    problems = []
    if not DATE.search(body):
        problems.append("carries no YYYY-MM-DD date, so the claim cannot go stale")
    # A measurement often names the test that guards it, in the same brackets,
    # as "measured <date>: <numbers>; tested <name>". That name is a tested
    # claim wherever it sits, and reading only the outer tag let one of them
    # name nothing for as long as it had been written.
    nested = re.split(r"\btested\b", body, maxsplit=1)
    if len(nested) == 2:
        problems.extend(tested_problems(nested[1], known))
    return problems


def source_problems(body: str) -> list[str]:
    if DATE.search(body) or REFERENCE.search(body) or len(body.split()) >= 3:
        return []
    return ["carries neither a date, a reference, nor a named document"]


COMMIT = re.compile(r"\bcommit=([0-9a-zA-Z]+)")


def commit_problems(sites: list[tuple[Path, int, str, str]]) -> tuple[list[str], int]:
    """Check every pinned object ID, and count the WORKTREE placeholders.

    A tag's commit= names the repository state that produced its evidence. A
    commit that no longer resolves is an unbacked claim of the same kind the
    rest of this file refuses, so it is a finding. WORKTREE is the legitimate
    in-progress spelling, because a commit cannot contain its own object ID;
    it is counted here and, under RELEASE=1, refused, so a release cannot
    ship a tree whose evidence still points at an uncommitted worktree.
    """
    wanted: dict[str, list[str]] = {}
    placeholders = 0
    for path, line, tag, body in sites:
        for oid in COMMIT.findall(body):
            if oid == "WORKTREE":
                placeholders += 1
                continue
            wanted.setdefault(oid, []).append(f"{path.relative_to(ROOT)}:{line}: {tag}")
    problems = []
    if wanted:
        query = "".join(f"{oid}^{{commit}}\n" for oid in wanted)
        result = subprocess.run(
            ["git", "cat-file", "--batch-check"],
            cwd=ROOT,
            input=query,
            capture_output=True,
            text=True,
            check=False,
        )
        for oid, answer in zip(wanted, result.stdout.splitlines(), strict=False):
            if " commit " not in f" {answer} ":
                for site in wanted[oid]:
                    problems.append(f"{site}: commit={oid} does not resolve to a commit")
    if placeholders and os.environ.get("RELEASE") == "1":
        problems.append(
            f"{placeholders} evidence tag(s) still say commit=WORKTREE; a release "
            f"pins each to the commit whose tree produced the evidence"
        )
    return problems, placeholders


def provenance_sites() -> list[tuple[Path, int, str, str]]:
    """Commit pins in commentless formats, for the pin check and nothing else."""
    sites: list[tuple[Path, int, str, str]] = []
    for glob in PROVENANCE_SOURCES:
        for path in sorted(ROOT.glob(glob)):
            text = _text(path)
            for line, body in enumerate(text.split("\n"), start=1):
                if "commit=" in body:
                    sites.append((path, line, "measured", body))
    return sites


def claim_sites() -> list[tuple[Path, int, str, str]]:
    sites: list[tuple[Path, int, str, str]] = []
    for glob in SOURCES:
        for path in sorted(ROOT.glob(glob)):
            text = _text(path)
            for match in CLAIM.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                body = COMMENT_PREFIX.sub(" ", match.group(2))
                sites.append((path, line, match.group(1).lower(), body))
    return sites


def untagged_guarantees() -> list[str]:
    """Guarantees carrying no evidence tag at all.

    The tags this file already checks are the ones somebody WROTE. A guarantee
    with no tag was reasoned to, and reads in the same voice as a measured
    fact: `lib_text`'s header stated one confidently while plunit was
    reporting eight tests succeeding with a choicepoint underneath it. Fourteen
    were found the first time this ran, and twelve of them turned out to have a
    test already, uncited.

    `[assumed <date>]` is a pass here, deliberately. It costs nothing to write
    and it is the only thing that makes an unverified claim visible as one.
    """
    block = re.compile(
        r"Guarantees:\n(.*?)\n(?:%|#|\s)*?"
        r"(?:Guarded by|Owns|Decides|Open Obligations|Fails when|Assumes):",
        re.S,
    )
    findings: list[str] = []
    for glob in SOURCES:
        for path in sorted(ROOT.glob(glob)):
            found = block.search(_text(path))
            if found is None:
                continue
            for item in re.split(r"\n\s*[%#]?\s*-\s", "\n" + found.group(1)):
                item = item.strip()
                if not item or re.search(r"\[(tested|measured|source|assumed)\b", item):
                    continue
                summary = " ".join(item.split())[:70]
                findings.append(
                    f"{path.relative_to(ROOT)}: guarantee with no evidence tag: {summary}"
                )
    return findings


def main() -> int:
    known, findings = gather()
    findings += untagged_guarantees()
    sites = claim_sites()
    pins, placeholders = commit_problems(sites + provenance_sites())
    findings += pins
    checked = 0
    for path, line, tag, body in sites:
        checked += 1
        if tag == "tested":
            problems = tested_problems(body, known)
        elif tag == "measured":
            problems = measured_problems(body, known)
        else:
            problems = source_problems(body)
        for problem in problems:
            findings.append(f"{path.relative_to(ROOT)}:{line}: {tag}: {problem}")
    for finding in findings:
        print(finding)
    print(
        f"{len(findings)} unbacked evidence tag(s) in {checked} claims, against "
        f"{len(known.targets)} known test names in {len(known.runs)} files a runner "
        f"executes; {placeholders} commit=WORKTREE placeholder(s) awaiting a "
        f"provenance pin"
    )
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
