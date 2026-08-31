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
    # The engine is mostly its SUBDIRECTORIES: 22 of its 42 Prolog files sit
    # one or two levels down, control.pl, space_hooks.pl, effects.pl and
    # translator/analysis.pl among them, and a single-level glob left every
    # claim and every commit pin in them unread.
    "engine/*/*.pl",
    "engine/*/*/*.pl",
    # The engine's benchmark driver is Python and makes the same kind of claim
    # its Prolog neighbours do. Without this line its tags were invisible: the
    # lane counted two placeholders in the tree where there were four.
    "engine/*.py",
    # The engine has C of its own -- the reader, the writer, the JSON codec
    # and the branch-return analysis -- whose headers make the same kind of
    # claim, and each seat's control file declares what that seat needs.
    "engine/*.c",
    "engine/*.h",
    "extensions/*/extension.pl",
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
    # The C seat, whose header IS its contract: 21 of its claims carried
    # commit pins and named tests while nothing read them, because C was the
    # one shipped language missing from this list. Its Prolog half joins for
    # the same reason the other two seats' halves are here.
    "extensions/cmetta/*.c",
    "extensions/cmetta/*.h",
    "extensions/cmetta/*.pl",
    # The three classes pin_provenance's out-of-scope net caught on 2026-08-31,
    # each carrying a real pin that nothing read and nothing would ever resolve:
    # a seat's build file, the C program a seat's install lane compiles, and the
    # Node consumer that proves dist/. Written per-seat rather than per-file so a
    # seat that grows one of these grows its coverage with it, which is the rule
    # _c_targets already follows for the cases inside these same suites.
    "extensions/*/Makefile",
    "extensions/*/tests/*.c",
    "extensions/*/tools/*.mjs",
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
#
# The shell runners are here for the pin half and not yet for the claim half.
# They carry measured claims like any other file -- check.sh's own VIRTUAL_ENV
# note is one -- and their commit pins went unchecked and, worse, unresolvable
# by the provenance pass, whose scope is this list. Their Guarantees blocks are
# a burn-down of 34 untagged claims recorded in
# ai-code-organisation-and-fixes.md rather than a gate today, which is the same
# staging every REPORT lane in check.sh follows.
PROVENANCE_SOURCES = (
    # The twins and the suites, named by the out-of-glob net on 2026-08-31: a
    # twin's BUDGET carries a whole provenance history in comments and a
    # suite's Guarantees block carries its own claims, so both were writing
    # pins nothing read and nothing would resolve. They join the PIN half
    # only, the same staging the shell runners take below, because their claim
    # half is a burn-down rather than a gate: reading them as SOURCES reports
    # 414 unbacked tags over 4,770 claims, most of them citations left behind
    # by a rename [measured 2026-08-31].
    "extensions/python/examples/*/*/*/*.py",
    "extensions/python/tests/*/*.py",
    "extensions/*/benchmarks/*.json",
    "engine/*.json",
    "*.sh",
    "engine/*.sh",
    "extensions/*/*.sh",
)

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
NODE_TEST = re.compile(r"""^\s*(?:it|describe)\(\s*["'`]([^"'`]+)["'`]""", re.MULTILINE)
# A C suite names its cases in identifiers, not in prose: `static void
# test_<name>(...)` defined at the top level. Being defined is not being run,
# which is why the caller set below matters as much as this pattern.
C_TEST = re.compile(r"^static\s+\w[\w *]*?\btest_(\w+)\s*\(", re.MULTILINE)
# main()'s body, which is the C suite's runner: a case reaches the binary only
# by being called from there.
C_MAIN = re.compile(r"^int\s+main\s*\([^)]*\)\s*\{(.*?)^\}", re.MULTILINE | re.DOTALL)
C_CALL = re.compile(r"\btest_(\w+)\s*\(")
# A Makefile target opens in column 1 and is followed by `:`, which `:=` is not:
# a variable assignment names sources without compiling them, and reading one as
# a target would put every source under whichever variable mentioned it.
MAKE_TARGET = re.compile(r"^([A-Za-z][\w.-]*)\s*:(?!=)")
# How a PROGRAM reports failure, as against a suite: it sets its own exit
# status. `throw` is deliberately not a signal, because every library source
# throws and reading that as evidence would back a claim naming any file at all;
# setting process.exitCode or calling process.exit is something only a program
# does, and extensions/node/tools/dist-consumer.mjs is one.
NODE_EXIT = re.compile(r"process\.exitCode\s*=\s*[1-9]|process\.exit\(\s*[1-9]")
# The C equivalent, read only where main() exists and the file declares no case,
# so a helper returning 1 in a suite cannot stand in for the suite running.
C_EXIT = re.compile(r"\breturn\s+[1-9]|\bexit\s*\(\s*[1-9]|\bEXIT_FAILURE\b")
# A name written in prose, quoted so the splitter takes it whole. It may WRAP,
# because a claim sits in a comment and a comment is wrapped like any other
# prose, so the match spans newlines and the name's whitespace is normalised
# to the single spaces the test's own title carries.
QUOTED_NAME = re.compile(r'"([^"]{4,}?)"', re.DOTALL)
COMMENT_PREFIX = re.compile(r"^[ \t]*[%#*]*[ \t]*", re.MULTILINE)
DATE = re.compile(r"\d{4}-\d{2}-\d{2}")
IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(?::[A-Za-z_][A-Za-z0-9_]*)*$")
#: What makes a token READ as a name rather than as the sentence around it.
#: A claim's prose sits in the same brackets as its names, and PROSE cannot
#: list every English word an author might use: one claim in
#: engine/metta/control.pl contributed "answers", "grow", "counter",
#: "creating", "grows" and "tenth", and one in extensions/cmetta/bridge.pl
#: contributed "reports", "row" and "present". A name in this tree carries an
#: underscore, a colon, a dot, a slash, a digit or a hyphen; a bare lowercase
#: word does not, and is read as prose UNLESS the tree defines it, which is
#: what keeps a single-word example name like `quiet` checkable and a
#: mistyped one the price.
NAME_SHAPED = re.compile(r"[_:./0-9-]")
REFERENCE = re.compile(r"https?://|\w+\.\w+:\d+|\w+/[\w./-]+")
SUFFIXES = (".py", ".pl", ".plt", ".metta", ".sh", ".c")

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
PROLOG_TEST = re.compile(r"^test\(\s*(\w+)", re.MULTILINE)
# A MeTTa form whose failure stops the file: test/3 throws metta_test_failed.
METTA_ASSERTION = re.compile(r"\((?:test|test-no-answer|assert[\w-]*)[\s(]")
SHELL_FAILURE = re.compile(r"\bexit\s+[1-9]|\breturn\s+[1-9]|\|\|\s*exit\b|^set -e", re.MULTILINE)


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


def _prolog_test_units(text: str) -> Iterator[tuple[str | None, str]]:
    """Every plunit test in a file, with the unit it is written inside.

    `None` for a test outside any unit, which plunit does not run and which
    stays reportable rather than silently attaching to whichever unit came
    first.
    """
    unit: str | None = None
    for line in text.splitlines():
        if opened := re.match(r"^:-\s*begin_tests\(\s*(\w+)", line):
            unit = opened.group(1)
        elif re.match(r"^:-\s*end_tests\(", line):
            unit = None
        elif started := re.match(r"^test\(\s*(\w+)", line):
            yield unit, started.group(1)


def _prolog_targets(reports: dict[Path, str]) -> dict[str, list[Target]]:
    """Plunit units and tests, and the named checks a Prolog script runs."""
    targets: dict[str, list[Target]] = {}
    for path in sorted((ROOT / "tests").rglob("*.pl*")):
        text = _text(path)
        run_path = path.resolve()
        why = reports[run_path]
        note = "" if why else "it has no plunit test, no entry goal, and nothing loads it"
        units = re.findall(r"begin_tests\(\s*(\w+)", text)
        named = [("plunit-unit", unit) for unit in units]
        # Each test paired with the unit it is ACTUALLY in, walked in order.
        # Registering the cross-product -- every test under every unit in the
        # file -- made `unit:name` resolve for any unit the file happens to
        # contain, so a citation could name the wrong one and pass. Four in
        # this tree did, and one written on 2026-08-31 was among them: a
        # reader who followed `shim_answer_form:one_variable_in_two_columns...`
        # would open the wrong unit and not find it.
        for unit, name in _prolog_test_units(text):
            named += [("plunit", name)]
            if unit is not None:
                named += [("plunit", f"{unit}:{name}")]
        # A check the gate runs as a script rather than as a plunit test is
        # evidence too: static_checks.pl is one, and its checks are named
        # predicates. A name worth registering carries arguments or a body.
        named += [("prolog", n) for n in re.findall(r"^([a-z]\w*)\s*(?::-|\()", text, re.MULTILINE)]
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


def _c_runner(makefile: str, source: Path) -> str:
    """The seat script that reaches this .c, read off the seat's own Makefile.

    A seat's tests/ holds more than its unit suite. extensions/cmetta/tests/
    holds test_cmetta.c, which `make test` builds through TESTS, and
    install_consumer.c, which ONLY `make install-check` compiles, from the
    c-install lane. Attributing both to the seat's test.sh said the consumer
    was covered by a lane that never opens it, so deleting c-install would have
    left its claim reading as backed [measured 2026-08-31: install_consumer.c
    resolved to test.sh with "the C suite exits nonzero", while
    `TESTS := tests/test_cmetta` is the whole of what the test target builds].

    A recipe line naming the source decides, because that is the line that
    compiles it; a source no recipe names is reached the ordinary way, through
    the test target, and stays with test.sh.
    """
    owner = None
    for line in makefile.splitlines():
        if matched := MAKE_TARGET.match(line):
            owner = matched.group(1)
        elif line.startswith("\t") and source.name in line:
            # Every seat lane other than the suite lives in the seat's check.sh,
            # which the root driver sources, so that is what runs this target.
            return "test.sh" if owner in (None, "test") else "check.sh"
    return "test.sh"


def _c_targets(runs: dict[Path, Execution]) -> dict[str, list[Target]]:
    """Every case a seat's C suite declares, and whether main() runs it.

    C was the one shipped language missing from this lane, so the C seat's
    header carried claims naming its own tests and nothing read them. A C suite
    has no collector: `main()` IS the runner, so a `static void test_x(void)`
    that main does not call is dead in exactly the way an uncollected pytest
    function is, and is reported the same way.

    Discovered rather than named, the same way evidence_runners finds a
    component's scripts: a seat that grows a C suite grows its own cases.
    """
    targets: dict[str, list[Target]] = {}
    for path in sorted(ROOT.glob("extensions/*/tests/*.c")):
        text = _text(path)
        body = C_MAIN.search(text)
        called = set(C_CALL.findall(body.group(1))) if body else set()
        seat = path.parent.parent
        recipe = seat / "Makefile"
        runner = (seat / _c_runner(_text(recipe) if recipe.is_file() else "", path)).resolve()
        run = runs.get(runner)
        reports = (
            "the C suite exits nonzero on the first failing check"
            if runner.name == "test.sh"
            else "a failed lane makes check.sh exit nonzero"
        )
        for name in C_TEST.findall(text):
            why = reports if run else None
            note = "" if run else "no lane runs its suite"
            if name not in called:
                why, note = None, "main() does not call it, so the binary never runs it"
            targets.setdefault(f"test_{name}", []).append(
                Target("c", path, runner, why, note)
            )
        targets.setdefault(path.name, []).append(
            Target("c", path, runner, reports if run else None, "" if run else "no lane runs its suite")
        )
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
    for name, found in _c_targets(runs).items():
        targets.setdefault(name, []).extend(found)
    for path in sorted((ROOT / "examples").rglob("*.metta")):
        targets.setdefault(path.stem, []).append(file_target(path, reports))
    for path in sorted((ROOT / "tests").rglob("*.sh")):
        targets.setdefault(path.stem, []).append(file_target(path, reports))
    files = {target.path.name for group in targets.values() for target in group}
    return Evidence(targets, runs, frozenset(files), reports), problems


def _node_file(path: Path, text: str, resolved: Path) -> Target:
    """A .ts or .mjs file's own way of failing: a declared case, or an exit.

    A seat ships both. test/*.test.ts declare cases node --test collects, while
    tools/dist-consumer.mjs is a PROGRAM whose whole body is the check and which
    reports by setting its exit status.
    """
    if NODE_TEST.search(text):
        return Target("node", path, resolved, "node --test reports a failure")
    if NODE_EXIT.search(text):
        return Target("node", path, resolved, "the program exits nonzero")
    return Target("node", path, resolved, None, "it declares no test and sets no exit status")


def _c_file(path: Path, text: str, resolved: Path) -> Target:
    """A .c file's own way of failing, the same two the .py branch models.

    A SUITE declares test_ cases and main() dispatches them, and a case main
    never calls is dead the way an uncollected pytest function is. A PROGRAM
    declares no cases at all: main() IS the check and it fails by exiting
    nonzero, which is what extensions/cmetta/tests/install_consumer.c does.
    Reading every .c as a suite said that consumer ran nothing, and contradicted
    _c_targets, which had already attributed it to the lane that compiles it, so
    one file answered two ways depending on how a claim spelled it
    [measured 2026-08-31].

    The exit is read from main()'s BODY, not the file, because a helper
    returning 1 is not the program reporting a failure.
    """
    body = C_MAIN.search(text)
    if body is not None and C_CALL.search(body.group(1)):
        return Target("c", path, resolved, "the C suite exits nonzero on the first failing check")
    if body is not None and not C_TEST.search(text) and C_EXIT.search(body.group(1)):
        return Target("c", path, resolved, "the program exits nonzero")
    return Target("c", path, resolved, None,
                  "its main() calls no test_ case, so the binary runs none")


def file_target(path: Path, reports: dict[Path, str]) -> Target:
    """What a claim naming a whole file gets: the file's own way of failing."""
    text = _text(path)
    resolved = path.resolve()
    if path.suffix == ".metta":
        if METTA_ASSERTION.search(text):
            return Target("example", path, resolved, "a test form throws when it does not match")
        return Target("example", path, resolved, None, "it holds no (test ...) or (assert ...) form")
    if path.suffix == ".sh":
        if resolved in {script.resolve() for script in gate_scripts()}:
            # A component's check.sh is SOURCED by the root driver, never
            # executed, so it has no `exit` of its own: its lanes report through
            # `run`, and the root turns a failed lane into the gate's nonzero
            # exit. Reading it for an exit of its own declared every component
            # check file unable to fail, which is what left the first three
            # claims naming one unbacked [measured 2026-08-31].
            return Target("shell", path, resolved, "a failed lane makes check.sh exit nonzero")
        if SHELL_FAILURE.search(text):
            return Target("shell", path, resolved, "the suite exits nonzero")
        return Target("shell", path, resolved, None, "it never exits nonzero")
    if path.suffix in (".pl", ".plt"):
        why = reports.get(resolved, _prolog_report(text))
        return Target(
            "prolog", path, resolved, why or None,
            "it has no plunit test, no entry goal, and nothing loads it",
        )
    if path.suffix in (".ts", ".mjs"):
        return _node_file(path, text, resolved)
    if path.suffix == ".c":
        return _c_file(path, text, resolved)
    if path.suffix == ".py":
        if re.search(r"^\s*(?:async\s+)?def\s+test", text, re.MULTILINE):
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


def _path_in(token: str, where: Path | None) -> Path | None:
    """The file a claim's path token names, from the root or from its own seat.

    A path is read the way its READER would read it. cmetta.h sits in
    extensions/cmetta/ and cites `tests/test_cmetta.c`, which is exactly the
    file beside it and exactly what a reader of that seat types; resolving only
    against the repository root called ten such citations unbacked on the day
    the C seat first came under this lane. Root first, so a repository-relative
    spelling keeps its meaning, and the citing file's own directory second.
    """
    candidate = ROOT / token
    if candidate.is_file():
        return candidate
    if where is not None:
        beside = where.parent / token
        if beside.is_file():
            return beside
    return None


def resolve(token: str, known: Evidence, where: Path | None = None) -> list[Target] | str:
    """The targets a claim's token names, or why it names none."""
    qualified = QUALIFIED.match(token)
    if qualified is not None:
        spelling, name = qualified.groups()
        basename = Path(spelling).name
        found = [
            target
            for target in known.targets.get(name, [])
            if target.path.name == basename or target.path == _path_in(spelling, where)
        ]
        if found:
            return found
        if basename in known.files or _path_in(spelling, where) is not None:
            return f"names {name}, which is not in {spelling}"
        return f"names the path {spelling}, which is not in the tree"
    if "/" in token or token.endswith(SUFFIXES):
        path = _path_in(token, where)
        if path is None:
            return f"names the path {token}, which is not in the tree"
        return [file_target(path, known.reports)]
    if not IDENTIFIER.match(token):
        return []
    # A `unit:test` whose UNIT the tree knows is answered by that pair alone.
    # Falling back to the bare name let a citation name the right test under
    # the wrong unit and pass, which sends a reader to a unit the test is not
    # in; four in this tree did. The fallback stays for every other colon
    # shape -- a module-qualified predicate, say -- where the prefix names no
    # unit.
    if ":" in token:
        unit, _, bare = token.rpartition(":")
        if any(target.kind == "plunit-unit" for target in known.targets.get(unit, [])):
            if paired := known.targets.get(token):
                return paired
            if bare in known.targets:
                return f"names {bare}, which is a test but not one in {unit}"
            return f"names {token}, which is not a test in the tree"
    found = known.targets.get(token) or known.targets.get(token.rsplit(":", maxsplit=1)[-1])
    if found:
        return found
    if not NAME_SHAPED.search(token):
        return []
    return f"names {token}, which is not a test in the tree"


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


def tested_problems(body: str, known: Evidence, where: Path | None = None) -> list[str]:
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
        found = resolve(token, known, where)
        if isinstance(found, str):
            problems.append(found)
            continue
        # A name can be defined more than once. One good definition backs the
        # claim, so only report when every one of them fails.
        verdicts = [target_problem(token, target, known) for target in found]
        if verdicts and all(verdicts):
            problems.append(verdicts[0])
    return problems


def measured_problems(body: str, known: Evidence, where: Path | None = None) -> list[str]:
    problems = []
    if not DATE.search(body):
        problems.append("carries no YYYY-MM-DD date, so the claim cannot go stale")
    # A measurement often names the test that guards it, in the same brackets,
    # as "measured <date>: <numbers>; tested <name>". That name is a tested
    # claim wherever it sits, and reading only the outer tag let one of them
    # name nothing for as long as it had been written.
    nested = re.split(r"\btested\b", body, maxsplit=1)
    if len(nested) == 2:
        problems.extend(tested_problems(nested[1], known, where))
    return problems


def source_problems(body: str) -> list[str]:
    if DATE.search(body) or REFERENCE.search(body) or len(body.split()) >= 3:
        return []
    return ["carries neither a date, a reference, nor a named document"]


COMMIT = re.compile(r"\bcommit=([0-9a-zA-Z]+)")

#: The lawful in-progress spelling of a commit pin, spelled ONCE here and
#: referenced everywhere else, including by the self-test, which imports it.
#: A provenance sweep resolves every pin in the tree to an object ID by
#: replacing this word, and on 2026-08-31 one reached into the messages
#: below and into the self-test's planted fixture: the checker still tested
#: the word while the self-test planted an object ID, so the two halves
#: disagreed about what a placeholder is and the RELEASE=1 rule went
#: untested. One occurrence of the word cannot desynchronise from itself.
PLACEHOLDER = "WORKTREE"


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
            if oid == PLACEHOLDER:
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
            f"{placeholders} evidence tag(s) still say commit={PLACEHOLDER}; a release "
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
        re.DOTALL,
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
            problems = tested_problems(body, known, path)
        elif tag == "measured":
            problems = measured_problems(body, known, path)
        else:
            problems = source_problems(body)
        for problem in problems:
            findings.append(f"{path.relative_to(ROOT)}:{line}: {tag}: {problem}")
    for finding in findings:
        print(finding)
    print(
        f"{len(findings)} unbacked evidence tag(s) in {checked} claims, against "
        f"{len(known.targets)} known test names in {len(known.runs)} files a runner "
        f"executes; {placeholders} commit={PLACEHOLDER} placeholder(s) awaiting a "
        f"provenance pin"
    )
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
