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
            a shell suite, an example, or a path in the tree
  measured  a YYYY-MM-DD date, so the claim can go stale
  source    a date or a reference

The measured and source rules stop at the date deliberately. In this tree the
NUMBER a measurement claims almost always sits in the sentence the tag stamps,
not inside the brackets, and reading it out of surrounding prose would flag
correct headers far more often than wrong ones. The date is the part that is
unambiguous, and ageing is what the tag is for.

`assumed` is unchecked on purpose. It is the honest tag for a claim nobody has
verified, and demanding evidence for it would push authors back to stating
unverified claims in the same voice as measured facts.
Guarantees:
  - a tested claim naming something absent fails the run, and a claim spanning
    several comment lines is read as one claim
    [tested: tests/check_evidence_tags.py]
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SOURCES = (
    "src/*.pl",
    "lib/*.pl",
    "lib/*.py",
    "python/petta/*.py",
    "python/petta/*.pl",
    "mork_ffi/*.pl",
    "tests/*.py",
)

# The tag and everything up to its closing bracket, across newlines: a claim
# listing three tests wraps, and a per-line scan reads the first line as an
# unterminated claim and skips it silently, which is how a checker for missing
# evidence comes to miss the evidence that is missing. The tag must also be
# FOLLOWED by a separator and a body, or the same pattern matches an ordinary
# Prolog variable spelled [Source] and the checker reports the file it reads.
CLAIM = re.compile(
    r"\[(tested|measured|source)[:\s]([^\]]*)\]", re.IGNORECASE | re.DOTALL
)
COMMENT_PREFIX = re.compile(r"^[ \t]*[%#*]*[ \t]*", re.MULTILINE)
DATE = re.compile(r"\d{4}-\d{2}-\d{2}")
IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(?::[A-Za-z_][A-Za-z0-9_]*)*$")
REFERENCE = re.compile(r"https?://|\w+\.\w+:\d+|\w+/[\w./-]+")

# Words that appear inside a claim's prose rather than naming anything.
PROSE = frozenset(
    """and or the a an in of with by at to for on end via plus then also
    through both all each every same test tests suite suites case cases
    e g eg ie i see also above below here there is are was were it its
    this that these those not no yes if when while as from into over
    under after before during than then rather instead but so because
    which what who whom whose how why where when whether""".split()
)


def known_names() -> set[str]:
    """Every name a claim may legitimately point at."""
    names: set[str] = set()
    # petta/_compliance.py holds real tests, shipped for a provider author to
    # inherit; they run here too, under each SpaceComplianceSuite subclass.
    for directory in ("python/tests", "python/benchmarks", "python/petta", "tests"):
        for path in (ROOT / directory).rglob("*.py"):
            names.update(
                re.findall(
                    r"^\s*(?:async\s+)?def\s+(test_\w+)", path.read_text(), re.M
                )
            )
    for path in (ROOT / "tests").rglob("*.pl*"):
        text = path.read_text()
        units = re.findall(r"begin_tests\(\s*(\w+)", text)
        names.update(units)
        for name in re.findall(r"^\s*test\(\s*(\w+)", text, re.M):
            names.add(name)
            names.update(f"{unit}:{name}" for unit in units)
        # A check the gate runs as a script rather than as a plunit test is
        # evidence too: static_checks.pl is one, and its checks are named
        # predicates.
        names.update(re.findall(r"^([a-z]\w*)\s*(?::-|\()", text, re.M))
    for path in (ROOT / "examples").rglob("*.metta"):
        names.add(path.stem)
    for path in (ROOT / "tests").rglob("*.sh"):
        names.add(path.stem)
    return names


def claim_sites() -> list[tuple[Path, int, str, str]]:
    sites: list[tuple[Path, int, str, str]] = []
    for glob in SOURCES:
        for path in sorted(ROOT.glob(glob)):
            text = path.read_text()
            for match in CLAIM.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                body = COMMENT_PREFIX.sub(" ", match.group(2))
                sites.append((path, line, match.group(1).lower(), body))
    return sites


def tested_problems(body: str, names: set[str]) -> list[str]:
    stripped = DATE.sub("", body)
    problems = []
    for token in re.split(r"[\s,;]+", stripped):
        token = token.strip(" :.'\"`()")
        if not token or token.lower() in PROSE:
            continue
        if "/" in token or token.endswith((".py", ".pl", ".plt", ".metta", ".sh")):
            if not (ROOT / token).exists():
                problems.append(f"names the path {token}, which is not in the tree")
            continue
        if not IDENTIFIER.match(token):
            continue
        if token not in names and token.split(":")[-1] not in names:
            problems.append(f"names {token}, which is not a test in the tree")
    return problems


def measured_problems(body: str, names: set[str]) -> list[str]:
    problems = []
    if not DATE.search(body):
        problems.append("carries no YYYY-MM-DD date, so the claim cannot go stale")
    # A measurement often names the test that guards it, in the same brackets,
    # as "measured <date>: <numbers>; tested <name>". That name is a tested
    # claim wherever it sits, and reading only the outer tag let one of them
    # name nothing for as long as it had been written.
    nested = re.split(r"\btested\b", body, maxsplit=1)
    if len(nested) == 2:
        problems.extend(tested_problems(nested[1], names))
    return problems


def source_problems(body: str) -> list[str]:
    if DATE.search(body) or REFERENCE.search(body) or len(body.split()) >= 3:
        return []
    return ["carries neither a date, a reference, nor a named document"]


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
          found = block.search(path.read_text(encoding="utf-8", errors="replace"))
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
    names = known_names()
    findings: list[str] = untagged_guarantees()
    checked = 0
    for path, line, tag, body in claim_sites():
        checked += 1
        if tag == "tested":
            problems = tested_problems(body, names)
        elif tag == "measured":
            problems = measured_problems(body, names)
        else:
            problems = source_problems(body)
        for problem in problems:
            findings.append(f"{path.relative_to(ROOT)}:{line}: {tag}: {problem}")
    for finding in findings:
        print(finding)
    print(
        f"{len(findings)} unbacked evidence tag(s) in {checked} claims, "
        f"against {len(names)} known test names"
    )
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
