"""Purpose: render the tutorial visuals as deterministic committed assets
with the sibling pettagrapher checkout and this checkout's metta Python
package: one SVG per tutorial page, the site favicon, and the animated
factorial reduction page tutorial 08 embeds.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from xml.etree import ElementTree

REPO = Path(__file__).resolve().parents[2]
DEV = REPO.parent.parent
OUTPUT = REPO / "website" / "public" / "visuals"


def _metta_python() -> Path:
    override = os.environ.get("METTA_PYTHON")
    candidates = [Path(override)] if override else [
        REPO / "python",
        DEV / "PyPeTTa1" / "PeTTa" / "python",
        DEV / "PeTTa" / "python",
    ]
    for candidate in candidates:
        if (candidate / "metta" / "__init__.py").exists():
            return candidate
    raise RuntimeError(
        "metta was not found; set METTA_PYTHON to a PeTTa checkout's "
        "python/ directory"
    )


def _pettagrapher_python() -> Path:
    override = os.environ.get("PETTAGRAPHER_PYTHON")
    candidates = [Path(override)] if override else [
        DEV / "pettagrapher",
        REPO.parent / "pettagrapher",
    ]
    for candidate in candidates:
        if (candidate / "pettagrapher" / "__init__.py").exists():
            return candidate
    raise RuntimeError(
        "pettagrapher was not found; set PETTAGRAPHER_PYTHON to its checkout"
    )


METTA_PYTHON = _metta_python()
PETTAGRAPHER_PYTHON = _pettagrapher_python()
sys.path[:0] = [str(METTA_PYTHON), str(PETTAGRAPHER_PYTHON)]
os.environ.setdefault("PETTA_PATH", str(METTA_PYTHON.parent))

import mettagrapher as pg
from metta import MeTTa, S, V


def _visuals() -> dict[str, str]:
    likes = S.likes(S.Ada, S.Music)

    family = [
        S.parent(S.Ada, S.Ben),
        S.parent(S.Ada, S.Cleo),
        S.parent(S.Ben, S.Dana),
    ]
    family_pattern = S.parent(S.Ada, V.child)

    double_rule = S["="](S.double(V.x), S["*"](V.x, 2))
    double_call = S.double(21)

    ages = [S.age(S.Ada, 37), S.age(S.Ben, 20)]
    age_pattern = S.age(V.name, V.years)

    factorial_rule = S["="](
        S.fact(V.n),
        S["if"](
            S["=="](V.n, 0),
            1,
            S["*"](V.n, S.fact(S["-"](V.n, 1))),
        ),
    )
    factorial_call = S.fact(5)

    type_declarations = [
        S[":"](S.Ann, S.Person),
        S[":"](S.age, S["->"](S.Person, S.Number)),
        S["get-type"](S.age(S.Ann)),
    ]

    ancestors = [
        S.parent(S.Tom, S.Bob),
        S.parent(S.Bob, S.Ann),
        S.parent(S.Ann, S.Zoe),
        S.ancestor(S.Tom, S.Zoe),
    ]
    ancestor_target = ancestors[-1]

    factorial_graph_call = S.fact(4)
    return {
        "favicon.svg": pg.term_svg(S.likes),
        "01-atoms-and-expressions.svg": pg.term_svg(likes),
        "02-spaces-and-matching.svg": pg.graph_svg(
            [*family, family_pattern],
            selection=[family_pattern],
            labels={family_pattern: "query"},
        ),
        "03-equations-and-evaluation.svg": pg.graph_svg(
            [double_rule, double_call],
            selection=[double_call],
            labels={double_call: "42"},
        ),
        "04-python-bridge.svg": pg.graph_svg(
            [*ages, age_pattern],
            selection=[age_pattern],
            labels={age_pattern: "Rows"},
        ),
        "05-writing-metta-in-python.svg": pg.graph_svg(
            [factorial_rule, factorial_call],
            directives=[S.highlight(S["if"])],
            selection=[factorial_call],
            labels={factorial_call: "120"},
        ),
        "06-types-and-casting.svg": pg.graph_svg(
            type_declarations,
            selection=[type_declarations[-1]],
            labels={type_declarations[-1]: "Number"},
        ),
        "07-seeing-your-program.svg": pg.graph_svg(
            ancestors,
            selection=[ancestor_target],
            labels={ancestor_target: "3 facts"},
        ),
        "08-graph-view.svg": pg.graph_svg(
            [factorial_rule, factorial_graph_call],
            directives=[S.highlight(S["if"])],
            selection=[factorial_graph_call],
            labels={factorial_graph_call: "24"},
        ),
    }


def _animations() -> dict[str, str]:
    """The animated reduction page tutorial 08 embeds: the factorial
    trace played through pettagrapher's own transition vocabulary."""
    with MeTTa().space() as m:
        m.run("(= (fact $n) (if (== $n 0) 1 (* $n (fact (- $n 1)))))")
        events = m.trace("!(fact 3)")
        if len(events) != 8 or str(events[-1].answer) != "6":
            raise RuntimeError(
                f"the factorial trace changed shape: {len(events)} events, "
                f"last answer {events[-1].answer if events else None!r}"
            )
        return {
            "08-graph-view-reduction.html": pg.reduction_page(
                m, "!(fact 3)", title="The factorial reduction, animated"
            ),
        }


def _check_svg(name: str, svg: str) -> None:
    root = ElementTree.fromstring(svg)
    if root.tag != "{http://www.w3.org/2000/svg}svg":
        raise ValueError(f"{name} did not render an SVG root")


def _check_html(name: str, html: str) -> None:
    lowered = html.lower()
    if "<html" not in lowered or "</html>" not in lowered:
        raise ValueError(f"{name} did not render a complete HTML page")
    if "svg" not in lowered:
        raise ValueError(f"{name} carries no SVG to animate")


def main() -> None:
    first = _visuals()
    second = _visuals()
    if first != second:
        raise RuntimeError("pettagrapher returned different SVG bytes in one run")
    first_pages = _animations()
    second_pages = _animations()
    if first_pages != second_pages:
        raise RuntimeError("pettagrapher returned different page bytes in one run")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, svg in first.items():
        _check_svg(name, svg)
        (OUTPUT / name).write_text(svg + "\n", encoding="utf8")
    for name, page in first_pages.items():
        _check_html(name, page)
        (OUTPUT / name).write_text(page, encoding="utf8")
    print(
        f"generated and parsed {len(first)} deterministic SVGs and "
        f"{len(first_pages)} animation page(s) in {OUTPUT}"
    )


if __name__ == "__main__":
    main()
